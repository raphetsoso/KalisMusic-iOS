import Foundation
import UIKit

// MARK: - Modifications d'infos (titre, artiste, album, genre, pochette)

struct TagOverride: Codable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
    /// Chemin relatif à Application Support.
    var cover: String?

    var isEmpty: Bool {
        return title == nil && artist == nil && album == nil && genre == nil && cover == nil
    }
}

/// Lu depuis plusieurs threads (chargement des pochettes, enregistreur, téléchargements) : l'accès passe par un verrou.
final class TagStore {
    static let shared = TagStore()
    private let key = "kalis_tags"
    private let lock = NSLock()
    private var store: [String: TagOverride]

    private init() {
        store = Persist.load([String: TagOverride].self, key: "kalis_tags") ?? [:]
    }

    /// Copie de l'état courant.
    var map: [String: TagOverride] {
        lock.lock()
        defer { lock.unlock() }
        return store
    }

    private func mutate(_ body: (inout [String: TagOverride]) -> Void) {
        lock.lock()
        body(&store)
        let snapshot = store
        lock.unlock()
        Persist.save(snapshot, key: key)
    }

    func override(for source: String) -> TagOverride? {
        lock.lock()
        defer { lock.unlock() }
        return store[source]
    }

    func cover(for source: String) -> String? { override(for: source)?.cover }

    func set(_ o: TagOverride?, for source: String) {
        mutate { m in
            if let o = o, !o.isEmpty { m[source] = o } else { m.removeValue(forKey: source) }
        }
    }

    func putField(_ source: String, title: String? = nil, artist: String? = nil, album: String? = nil, genre: String? = nil) {
        var o = override(for: source) ?? TagOverride()
        if let v = title { o.title = v }
        if let v = artist { o.artist = v }
        if let v = album { o.album = v }
        if let v = genre { o.genre = v }
        set(o, for: source)
    }

    func setCover(_ source: String, rel: String?) {
        var o = override(for: source) ?? TagOverride()
        if o.cover != rel { Paths.deleteCover(o.cover) }
        o.cover = rel
        set(o, for: source)
        ArtLoader.invalidate(source)
    }

    func setCover(_ source: String, jpegData: Data) {
        let name = "covers/t" + String(UUID().uuidString.prefix(12)) + ".jpg"
        let url = Paths.url(forCover: name)
        do {
            try jpegData.write(to: url, options: .atomic)
            setCover(source, rel: name)
        } catch {}
    }

    func reset(_ source: String) {
        Paths.deleteCover(override(for: source)?.cover)
        mutate { $0.removeValue(forKey: source) }
        ArtLoader.invalidate(source)
    }

    func replaceAll(_ m: [String: TagOverride]) {
        mutate { $0 = m }
    }

    /// Copie une image choisie par l'utilisateur dans le dossier des pochettes (réduite, en JPEG).
    static func importCover(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), let jpg = ImageUtil.jpeg(fromData: data) else { return nil }
        let name = "covers/c" + String(UUID().uuidString.prefix(12)) + ".jpg"
        do {
            try jpg.write(to: Paths.url(forCover: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}

// MARK: - Playlists et favoris

private struct PlaylistData: Codable {
    var lists: [String: [String]] = [:]
    var favorites: [String] = []
}

final class PlaylistStore: ObservableObject {
    static let shared = PlaylistStore()
    @Published private(set) var lists: [String: [String]]
    @Published private(set) var favorites: [String]

    private init() {
        let d = Persist.load(PlaylistData.self, key: "kalis_playlists") ?? PlaylistData()
        lists = d.lists
        favorites = d.favorites
    }

    private func save() {
        Persist.save(PlaylistData(lists: lists, favorites: favorites), key: "kalis_playlists")
    }

    var names: [String] {
        return lists.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    func create(_ name: String) -> Bool {
        let n = name.trimmed
        if n.isEmpty || lists[n] != nil { return false }
        lists[n] = []
        save()
        return true
    }

    func delete(_ name: String) {
        lists.removeValue(forKey: name)
        save()
    }

    func add(_ name: String, _ t: Track) {
        var a = lists[name] ?? []
        a.append(t.source)
        lists[name] = a
        save()
    }

    /// `pos` est la position dans la liste affichée, qui ne montre que les morceaux encore présents :
    /// on la convertit en position réelle, sinon on retirerait un autre morceau.
    func removeAt(_ name: String, _ pos: Int) {
        guard var a = lists[name], pos >= 0 else { return }
        let lib = MusicLibrary.shared
        var shown = 0
        for (i, p) in a.enumerated() where lib.byPath(p) != nil {
            if shown == pos {
                a.remove(at: i)
                lists[name] = a
                save()
                return
            }
            shown += 1
        }
    }

    func count(_ name: String) -> Int { lists[name]?.count ?? 0 }

    func tracks(_ name: String) -> [Track] {
        return resolve(lists[name] ?? [])
    }

    func favoriteTracks() -> [Track] { resolve(favorites) }

    private func resolve(_ paths: [String]) -> [Track] {
        let lib = MusicLibrary.shared
        var out: [Track] = []
        for p in paths { if let t = lib.byPath(p) { out.append(t) } }
        return out
    }

    func isFavorite(_ t: Track) -> Bool { favorites.contains(t.source) }

    @discardableResult
    func toggleFavorite(_ t: Track) -> Bool {
        if let i = favorites.firstIndex(of: t.source) {
            favorites.remove(at: i)
            save()
            return false
        }
        favorites.append(t.source)
        save()
        return true
    }

    func replaceAll(lists l: [String: [String]], favorites f: [String]) {
        lists = l
        favorites = f
        save()
    }
}

// MARK: - Statistiques d'écoute

struct TrackStat: Codable {
    var name: String = ""
    var title: String = ""
    var artist: String = ""
    var ms: Int64 = 0
    var plays: Int = 0
}

struct StatsData: Codable {
    var tracks: [String: TrackStat] = [:]
    var genres: [String: Int64] = [:]
    var artists: [String: Int64] = [:]
    var totalMs: Int64 = 0
    var totalPlays: Int = 0
}

struct StatItem: Identifiable {
    var key: String = ""
    var title: String = ""
    var artist: String = ""
    var plays: Int = 0
    var ms: Int64 = 0
    var id: String { key + title }
}

/// À utiliser depuis le thread principal uniquement.
final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    @Published private(set) var data: StatsData
    private var lastSave = Date.distantPast

    private init() {
        data = Persist.load(StatsData.self, key: "kalis_stats") ?? StatsData()
    }

    func flush() {
        Persist.save(data, key: "kalis_stats")
        lastSave = Date()
    }

    /// Ajoute du temps d'écoute (appelé régulièrement pendant la lecture).
    func addListen(_ t: Track, ms: Int64) {
        if ms <= 0 { return }
        data.totalMs += ms
        let genre = t.stream ? "Radio" : t.genre
        if !genre.isEmpty { data.genres[genre, default: 0] += ms }
        if !t.stream {
            if !t.artist.isEmpty { data.artists[t.artist, default: 0] += ms }
            var e = data.tracks[t.source] ?? TrackStat()
            e.name = (t.source as NSString).lastPathComponent
            e.title = t.title
            e.artist = t.artist
            e.ms += ms
            data.tracks[t.source] = e
        }
        if Date().timeIntervalSince(lastSave) > 30 { flush() }
    }

    func addPlay(_ t: Track) {
        if t.stream { return }
        var e = data.tracks[t.source] ?? TrackStat()
        e.name = (t.source as NSString).lastPathComponent
        e.title = t.title
        e.artist = t.artist
        e.plays += 1
        data.tracks[t.source] = e
        data.totalPlays += 1
        flush()
    }

    func reset() {
        data = StatsData()
        flush()
    }

    func topTracks(_ max: Int) -> [StatItem] {
        var out: [StatItem] = []
        for (k, e) in data.tracks where e.plays > 0 {
            out.append(StatItem(key: k, title: e.title, artist: e.artist, plays: e.plays, ms: e.ms))
        }
        out.sort { a, b in
            if a.plays != b.plays { return a.plays > b.plays }
            return a.ms > b.ms
        }
        return Array(out.prefix(max))
    }

    func topGenres(_ max: Int) -> [StatItem] { ranking(data.genres, max) }
    func topArtists(_ max: Int) -> [StatItem] { ranking(data.artists, max) }

    private func ranking(_ d: [String: Int64], _ max: Int) -> [StatItem] {
        var out: [StatItem] = []
        for (k, v) in d where v > 0 { out.append(StatItem(key: k, title: k, ms: v)) }
        out.sort { $0.ms > $1.ms }
        return Array(out.prefix(max))
    }

    /// Remplace les statistiques par celles de la sauvegarde ; les chemins sont retrouvés par nom de fichier.
    func restore(_ d: StatsData, byName: [String: String]) {
        var nd = d
        var tracks: [String: TrackStat] = [:]
        for (k, e) in d.tracks {
            let path = byName[e.name.lowercased()] ?? k
            tracks[path] = e
        }
        nd.tracks = tracks
        data = nd
        flush()
    }
}

// MARK: - Données du KalisStore

struct StoreHistoryEntry: Codable, Identifiable {
    var title: String = ""
    var artist: String = ""
    var pageUrl: String = ""
    var file: String = ""
    var date: Double = 0
    var id: String { pageUrl + "|" + String(date) }
}

final class StoreData: ObservableObject {
    static let shared = StoreData()

    @Published var hidden: Bool { didSet { UserDefaults.standard.set(hidden, forKey: "kalisstore_hidden") } }
    @Published private(set) var wishlist: [NcsResult]
    @Published private(set) var history: [StoreHistoryEntry]
    /// pageUrl -> fichier installé (chemin relatif à Documents)
    @Published private(set) var addedFiles: [String: String]

    private init() {
        hidden = UserDefaults.standard.bool(forKey: "kalisstore_hidden")
        wishlist = Persist.load([NcsResult].self, key: "kalisstore_wishlist") ?? []
        history = Persist.load([StoreHistoryEntry].self, key: "kalisstore_history") ?? []
        addedFiles = Persist.load([String: String].self, key: "kalisstore_added") ?? [:]
    }

    func isWished(_ pageUrl: String) -> Bool { wishlist.contains { $0.pageUrl == pageUrl } }

    @discardableResult
    func toggleWish(_ r: NcsResult) -> Bool {
        if let i = wishlist.firstIndex(where: { $0.pageUrl == r.pageUrl }) {
            wishlist.remove(at: i)
            Persist.save(wishlist, key: "kalisstore_wishlist")
            return false
        }
        wishlist.append(r)
        Persist.save(wishlist, key: "kalisstore_wishlist")
        return true
    }

    func addHistory(title: String, artist: String, pageUrl: String, file: String) {
        history.append(StoreHistoryEntry(title: title, artist: artist, pageUrl: pageUrl, file: file,
                                         date: Date().timeIntervalSince1970 * 1000))
        Persist.save(history, key: "kalisstore_history")
    }

    func remember(pageUrl: String, file: String) {
        addedFiles[pageUrl] = file
        Persist.save(addedFiles, key: "kalisstore_added")
    }

    func forget(pageUrl: String) {
        addedFiles.removeValue(forKey: pageUrl)
        Persist.save(addedFiles, key: "kalisstore_added")
    }

    static func fileExists(_ rel: String) -> Bool {
        return !rel.isEmpty && FileManager.default.fileExists(atPath: Paths.url(forSource: rel).path)
    }

    /// Les musiques installées depuis le KalisStore et toujours présentes sur l'appareil.
    func installed() -> [StoreHistoryEntry] {
        var byFile: [String: StoreHistoryEntry] = [:]
        for e in history.reversed() where !e.file.isEmpty && byFile[e.file] == nil { byFile[e.file] = e }
        var out: [StoreHistoryEntry] = []
        for (page, file) in addedFiles where StoreData.fileExists(file) {
            var e = byFile[file] ?? StoreHistoryEntry()
            e.pageUrl = page
            e.file = file
            if e.title.isEmpty { e.title = ((file as NSString).lastPathComponent as NSString).deletingPathExtension }
            out.append(e)
        }
        out.sort { $0.date > $1.date }
        return out
    }

    /// Historique complet, du plus récent au plus ancien, avec l'état « encore installé ».
    func historyWithState() -> [(entry: StoreHistoryEntry, installed: Bool)] {
        var out: [(entry: StoreHistoryEntry, installed: Bool)] = []
        for e in history.reversed() {
            let inst = StoreData.fileExists(e.file) && addedFiles.values.contains(e.file)
            out.append((entry: e, installed: inst))
        }
        return out
    }

    func replace(history h: [StoreHistoryEntry], wishlist w: [NcsResult], added: [String: String], hidden hd: Bool) {
        history = h
        wishlist = w
        addedFiles = added
        hidden = hd
        Persist.save(h, key: "kalisstore_history")
        Persist.save(w, key: "kalisstore_wishlist")
        Persist.save(added, key: "kalisstore_added")
    }
}

// MARK: - Webradios

struct CustomStation: Codable {
    var name: String
    var url: String
    var band: String
    var cover: String?
}

struct Station: Identifiable {
    let name: String
    let url: String
    let band: String
    let place: String
    let custom: Bool
    let cover: String
    var id: String { url }

    func toTrack() -> Track {
        var t = Track()
        t.title = name
        t.artist = band + (place.isEmpty ? "" : " • " + place)
        t.album = "Webradio"
        t.genre = "Radio"
        t.source = url
        t.stream = true
        t.logo = RadioStore.slug(name)
        t.logoFile = cover.isEmpty ? nil : cover
        t.albumKey = "s" + url
        return t
    }
}

final class RadioStore: ObservableObject {
    static let shared = RadioStore()
    static let fm = "FM"
    static let am = "AM"

    @Published private(set) var customs: [CustomStation]

    // Adresses de flux publiques écrites de mémoire : elles peuvent changer.
    // Une station qui ne répond plus se corrige (ou s'ajoute) avec « Ajouter une station… ».
    private static var builtIn: [Station] { return [
        Station(name: "France Inter", url: "https://icecast.radiofrance.fr/franceinter-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "franceinfo", url: "https://icecast.radiofrance.fr/franceinfo-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "France Culture", url: "https://icecast.radiofrance.fr/franceculture-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "France Musique", url: "https://icecast.radiofrance.fr/francemusique-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "FIP", url: "https://icecast.radiofrance.fr/fip-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "Mouv'", url: "https://icecast.radiofrance.fr/mouv-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "France Bleu", url: "https://icecast.radiofrance.fr/fb1071-midfi.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "RTL", url: "https://streaming.radio.rtl.fr/rtl-1-44-128", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "RTL2", url: "https://streaming.radio.rtl.fr/rtl2-1-44-128", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "NRJ", url: "https://cdn.nrjaudio.fm/audio1/fr/30001/mp3_128.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "Skyrock", url: "https://icecast.skyrock.net/s/natio_mp3_128k", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "RMC", url: "https://audio.bfmtv.com/rmcradio_128.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "Radio Classique", url: "https://radioclassique.ice.infomaniak.ch/radioclassique-high.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "Radio Nova", url: "https://novazz.ice.infomaniak.ch/novazz-128.mp3", band: fm, place: L("France"), custom: false, cover: ""),
        Station(name: "WNYC FM 93.9", url: "https://fm939.wnyc.org/wnycfm", band: fm, place: "New York", custom: false, cover: ""),

        Station(name: "WNYC AM 820", url: "https://am820.wnyc.org/wnycam", band: am, place: "New York", custom: false, cover: ""),
        Station(name: "BBC Radio 5 Live", url: "https://stream.live.vc.bbcmedia.co.uk/bbc_radio_five_live", band: am, place: L("Royaume-Uni"), custom: false, cover: ""),
        Station(name: "talkSPORT", url: "https://radio.talksport.com/stream", band: am, place: L("Royaume-Uni"), custom: false, cover: "")
    ] }

    private init() {
        customs = Persist.load([CustomStation].self, key: "kalis_radios") ?? []
    }

    private func save() { Persist.save(customs, key: "kalis_radios") }

    /// « Mouv' » -> « mouv », « France Inter » -> « france_inter » (nom de fichier du logo).
    static func slug(_ name: String) -> String {
        let folded = name.folding(options: .diacriticInsensitive, locale: nil).lowercased()
        var s = Rx.replace("[^a-z0-9]+", in: folded, with: "_", options: [])
        s = Rx.replace("^_+|_+$", in: s, with: "", options: [])
        return s
    }

    /// Les stations de l'utilisateur d'abord, puis celles de la liste intégrée.
    func stations(_ band: String) -> [Station] {
        var out: [Station] = []
        for c in customs where c.band == band {
            out.append(Station(name: c.name, url: c.url, band: c.band, place: "", custom: true, cover: c.cover ?? ""))
        }
        for s in RadioStore.builtIn where s.band == band { out.append(s) }
        return out
    }

    /// Une station (intégrée ou ajoutée) utilise déjà cette adresse ?
    func has(url: String) -> Bool {
        let u = url.trimmed
        return customs.contains { $0.url == u } || RadioStore.builtIn.contains { $0.url == u }
    }

    func add(name: String, url: String, band: String, cover: String?) {
        customs.append(CustomStation(name: name.trimmed, url: url.trimmed, band: band, cover: cover))
        save()
    }

    func setCover(url: String, cover: String?) {
        for i in customs.indices where customs[i].url == url {
            Paths.deleteCover(customs[i].cover)
            customs[i].cover = cover
        }
        save()
        ArtLoader.clear()
    }

    func remove(url: String) {
        for c in customs where c.url == url { Paths.deleteCover(c.cover) }
        customs.removeAll { $0.url == url }
        save()
    }

    func replaceCustoms(_ list: [CustomStation]) {
        customs = list
        save()
    }

    static func tracks(_ list: [Station]) -> [Track] { list.map { $0.toTrack() } }
}
