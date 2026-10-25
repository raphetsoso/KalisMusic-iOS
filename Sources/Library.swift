import Foundation
import AVFoundation
import UIKit

// MARK: - Pochettes

final class ArtBus: ObservableObject {
    static let shared = ArtBus()
    @Published var version = 0
}

enum ArtLoader {
    private static let cache = NSCache<NSString, UIImage>()
    private static let lock = NSLock()
    private static var misses = Set<String>()

    private static func isMiss(_ k: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return misses.contains(k)
    }

    private static func addMiss(_ k: String) {
        lock.lock()
        misses.insert(k)
        lock.unlock()
    }

    private static func resetMisses() {
        lock.lock()
        misses.removeAll()
        lock.unlock()
    }

    /// Vide le cache et force les vues à recharger leurs pochettes.
    static func clear() {
        cache.removeAllObjects()
        resetMisses()
        DispatchQueue.main.async { ArtBus.shared.version += 1 }
    }

    /// Réessaie les pochettes qui manquaient (nouveaux morceaux).
    static func clearMisses() {
        resetMisses()
        DispatchQueue.main.async { ArtBus.shared.version += 1 }
    }

    static func invalidate(_ source: String) {
        cache.removeObject(forKey: source as NSString)
        resetMisses()
        DispatchQueue.main.async { ArtBus.shared.version += 1 }
    }

    static func image(forAny tracks: [Track]) async -> UIImage? {
        for t in tracks.prefix(4) {
            if let i = await image(for: t) { return i }
        }
        return nil
    }

    static func image(for t: Track) async -> UIImage? {
        let key = t.source
        if let c = cache.object(forKey: key as NSString) { return c }
        if isMiss(key) { return nil }

        var found: UIImage? = nil
        // 1. pochette choisie par l'utilisateur
        if let rel = TagStore.shared.cover(for: t.source) ?? t.logoFile, !rel.isEmpty {
            found = ImageUtil.thumbnail(fileURL: Paths.url(forCover: rel), maxDim: 700)
        }
        if found == nil {
            if t.stream {
                // 2. logo intégré d'une webradio
                if let p = Bundle.main.path(forResource: "radio_" + t.logo, ofType: "png", inDirectory: "RadioLogos") {
                    found = ImageUtil.thumbnail(fileURL: URL(fileURLWithPath: p), maxDim: 700)
                }
            } else {
                // 3. pochette intégrée au fichier audio
                found = await embedded(url: Paths.url(forSource: t.source))
            }
        }
        if let f = found {
            cache.setObject(f, forKey: key as NSString)
        } else {
            addMiss(key)
        }
        return found
    }

    private static func embedded(url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return nil }
        let arts = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierArtwork)
        for it in arts {
            if let d = try? await it.load(.dataValue), let img = ImageUtil.thumbnail(data: d, maxDim: 700) {
                return img
            }
        }
        return nil
    }
}

// MARK: - Import des fichiers et lecture des métadonnées

enum Importer {
    static let exts: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"]

    struct Meta: Codable {
        var source: String
        var title: String = ""
        var artist: String = ""
        var album: String = ""
        var genre: String = ""
        var duration: Double = 0
        var trackNo: Int = 0
        var added: Double = 0
    }

    struct FileEntry {
        var source: String
        var url: URL
        var added: Double
    }

    enum Outcome {
        case added(String)
        case skipped
        case failed
    }

    private static var indexURL: URL { Paths.support.appendingPathComponent("index.json") }

    static func loadIndex() -> [String: Meta] {
        guard let d = try? Data(contentsOf: indexURL),
              let m = try? JSONDecoder().decode([String: Meta].self, from: d) else { return [:] }
        return m
    }

    static func saveIndex(_ m: [String: Meta]) {
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: indexURL, options: .atomic) }
    }

    static func isAudio(_ url: URL) -> Bool { exts.contains(url.pathExtension.lowercased()) }

    // MARK: Analyse du dossier Music

    static func listAudioFiles() -> [FileEntry] {
        var out: [FileEntry] = []
        walk(Paths.music, rel: "Music", into: &out)
        return out
    }

    private static func walk(_ dir: URL, rel: String, into out: inout [FileEntry]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
        for u in items {
            let name = u.lastPathComponent
            let values = try? u.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                walk(u, rel: rel + "/" + name, into: &out)
            } else if isAudio(u) {
                let ts = (values?.creationDate ?? Date()).timeIntervalSince1970
                out.append(FileEntry(source: rel + "/" + name, url: u, added: ts))
            }
        }
    }

    /// Analyse Documents/Music : relit seulement les métadonnées des nouveaux fichiers.
    static func scanAndIndex() async -> [Meta] {
        let old = loadIndex()
        var fresh: [String: Meta] = [:]
        var out: [Meta] = []
        for f in listAudioFiles() {
            if let m = old[f.source], m.duration > 0 {
                fresh[f.source] = m
                out.append(m)
                continue
            }
            var m = await readMeta(url: f.url, source: f.source)
            m.added = f.added
            fresh[f.source] = m
            out.append(m)
        }
        saveIndex(fresh)
        return out
    }

    static func readMeta(url: URL, source: String) async -> Meta {
        var m = Meta(source: source)
        let asset = AVURLAsset(url: url)
        if let d = try? await asset.load(.duration) {
            let s = d.seconds
            if s.isFinite && s > 0 { m.duration = s }
        }
        if let common = try? await asset.load(.commonMetadata) {
            for item in common {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle, let v = try? await item.load(.stringValue) {
                    m.title = v
                } else if key == .commonKeyArtist, let v = try? await item.load(.stringValue) {
                    m.artist = v
                } else if key == .commonKeyAlbumName, let v = try? await item.load(.stringValue) {
                    m.album = v
                } else if key == .commonKeyType, let v = try? await item.load(.stringValue) {
                    m.genre = v
                }
            }
        }
        if let all = try? await asset.load(.metadata) {
            let id3 = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .id3MetadataTrackNumber)
            if let it = id3.first, let s = try? await it.load(.stringValue) {
                m.trackNo = Int(s.split(separator: "/").first.map(String.init) ?? "") ?? 0
            } else {
                let itunes = AVMetadataItem.metadataItems(from: all, filteredByIdentifier: .iTunesMetadataTrackNumber)
                if let it = itunes.first, let d = try? await it.load(.dataValue), d.count >= 4 {
                    m.trackNo = Int(d[2]) << 8 | Int(d[3])
                }
            }
        }
        return m
    }

    // MARK: Copie dans la bibliothèque

    private static func sanitize(_ name: String) -> String {
        return Rx.replace(#"[\\/:*?"<>|]"#, in: name, with: "_", options: [])
    }

    private static func uniqueDest(_ name: String) -> URL {
        let fm = FileManager.default
        var dest = Paths.music.appendingPathComponent(name)
        if !fm.fileExists(atPath: dest.path) { return dest }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while true {
            let cand = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            dest = Paths.music.appendingPathComponent(cand)
            if !fm.fileExists(atPath: dest.path) { return dest }
            n += 1
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (a?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Copie (ou déplace) un fichier audio dans Documents/Music. Renvoie le chemin relatif du morceau.
    static func importFile(_ src: URL, move: Bool) -> Outcome {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.music, withIntermediateDirectories: true)
        let name = sanitize(src.lastPathComponent)
        let plain = Paths.music.appendingPathComponent(name)
        // même nom et même taille : déjà importé
        if fm.fileExists(atPath: plain.path), fileSize(plain) == fileSize(src) {
            if move { try? fm.removeItem(at: src) }
            return .skipped
        }
        let dest = uniqueDest(name)
        do {
            if move {
                do { try fm.moveItem(at: src, to: dest) } catch { try fm.copyItem(at: src, to: dest); try? fm.removeItem(at: src) }
            } else {
                try fm.copyItem(at: src, to: dest)
            }
            return .added("Music/" + dest.lastPathComponent)
        } catch {
            return .failed
        }
    }

    /// Fichiers audio d'un dossier (sous-dossiers compris). Fonction synchrone à part : l'énumérateur n'est pas utilisable en async.
    static func expandTree(_ dir: URL) -> [URL] {
        var out: [URL] = []
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles]) else { return out }
        while let any = e.nextObject() {
            if let u = any as? URL, isAudio(u) { out.append(u) }
        }
        return out
    }

    private static func isDirectory(_ u: URL) -> Bool {
        return (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Importe des fichiers et/ou dossiers choisis par l'utilisateur.
    static func importAsync(_ urls: [URL], move: Bool, progress: @escaping (Int, Int, String) -> Void) async -> (added: Int, skipped: Int) {
        // 1. dresser la liste des fichiers ; l'accès aux dossiers choisis reste ouvert jusqu'à la fin de la copie
        var jobs: [URL] = []
        var scopes: [URL] = []
        for u in urls {
            if u.startAccessingSecurityScopedResource() { scopes.append(u) }
            if isDirectory(u) {
                jobs.append(contentsOf: expandTree(u))
            } else if isAudio(u) {
                jobs.append(u)
            }
        }
        var added = 0
        var skipped = 0
        for (i, f) in jobs.enumerated() {
            progress(i + 1, jobs.count, f.lastPathComponent)
            switch importFile(f, move: move) {
            case .added: added += 1
            case .skipped: skipped += 1
            case .failed: skipped += 1
            }
        }
        for s in scopes { s.stopAccessingSecurityScopedResource() }
        return (added, skipped)
    }

    // MARK: Suppression

    static func delete(_ t: Track) {
        if t.stream { return }
        try? FileManager.default.removeItem(at: Paths.url(forSource: t.source))
        TagStore.shared.reset(t.source)
        var idx = loadIndex()
        idx.removeValue(forKey: t.source)
        saveIndex(idx)
        ArtLoader.invalidate(t.source)
        MusicLibrary.shared.refresh()
    }
}

// MARK: - Bibliothèque

final class MusicLibrary: ObservableObject {
    static let shared = MusicLibrary()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var albums: [Album] = []
    @Published private(set) var loaded = false
    @Published private(set) var scanning = false

    private var metas: [Importer.Meta] = []
    private var genreMap: [String: [Track]] = [:]
    private var artistMap: [String: [Track]] = [:]
    private var albumMap: [String: Album] = [:]
    private var pathMap: [String: Track] = [:]
    private var pending = false

    private init() {}

    var isEmpty: Bool { loaded && tracks.isEmpty }
    var genreNames: [String] { genreMap.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    var artistNames: [String] { artistMap.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }

    func album(_ key: String) -> Album? { albumMap[key] }
    func byPath(_ p: String) -> Track? { pathMap[p] }
    func genreTracks(_ n: String) -> [Track] { genreMap[n] ?? [] }
    func artistTracks(_ n: String) -> [Track] { artistMap[n] ?? [] }

    func albumCount(_ list: [Track]) -> Int {
        return Set(list.map { $0.albumKey }).count
    }

    func recentAlbums(_ max: Int) -> [Album] {
        let sorted = albums.sorted { $0.added > $1.added }
        return Array(sorted.prefix(max))
    }

    func search(_ q: String) -> [Track] {
        let needle = q.trimmed
        if needle.isEmpty { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.artist.localizedCaseInsensitiveContains(needle)
                || $0.album.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Relit le dossier Music (nouveaux fichiers, fichiers supprimés) puis reconstruit les listes.
    func refresh() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.refresh() }
            return
        }
        if scanning {
            pending = true
            return
        }
        scanning = true
        Task {
            let found = await Importer.scanAndIndex()
            await MainActor.run {
                self.metas = found
                self.apply(MusicLibrary.build(found))
                self.scanning = false
                if self.pending {
                    self.pending = false
                    self.refresh()
                }
            }
        }
    }

    /// Reconstruit les listes sans relire les fichiers (après une modification d'infos).
    func rebuild() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.rebuild() }
            return
        }
        apply(MusicLibrary.build(metas))
    }

    // MARK: Construction

    struct Built {
        var tracks: [Track]
        var albums: [Album]
        var albumMap: [String: Album]
        var genres: [String: [Track]]
        var artists: [String: [Track]]
        var paths: [String: Track]
    }

    private func apply(_ b: Built) {
        let changed = b.tracks.map { $0.source } != tracks.map { $0.source }
        genreMap = b.genres
        artistMap = b.artists
        albumMap = b.albumMap
        pathMap = b.paths
        albums = b.albums
        tracks = b.tracks
        loaded = true
        if changed { ArtLoader.clearMisses() }
    }

    private static func clean(_ s: String?, _ fallback: String?) -> String? {
        guard let s = s?.trimmed, !s.isEmpty else { return fallback }
        return s
    }

    static func build(_ metas: [Importer.Meta]) -> Built {
        let tags = TagStore.shared
        var list: [Track] = []
        list.reserveCapacity(metas.count)

        for m in metas {
            let o = tags.override(for: m.source)
            let rawTitle = o?.title ?? m.title
            let rawArtist = o?.artist ?? m.artist
            let rawAlbum = o?.album ?? m.album
            let rawGenre = o?.genre ?? m.genre

            var t = Track()
            t.source = m.source
            t.duration = m.duration
            t.trackNo = m.trackNo
            t.added = m.added
            let fileTitle = ((m.source as NSString).lastPathComponent as NSString).deletingPathExtension
            t.title = clean(rawTitle, fileTitle) ?? fileTitle
            let hasArtist = clean(rawArtist, nil) != nil
            t.artist = clean(rawArtist, "Artiste inconnu") ?? "Artiste inconnu"
            let hasAlbum = clean(rawAlbum, nil) != nil
            t.album = clean(rawAlbum, "Album inconnu") ?? "Album inconnu"
            t.genre = clean(rawGenre, "Genre inconnu") ?? "Genre inconnu"
            if hasAlbum { t.albumKey = "n" + t.album.lowercased() }
            else if hasArtist { t.albumKey = "u" + t.artist.lowercased() }
            else { t.albumKey = "t" + t.source }
            list.append(t)
        }

        list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var order: [String] = []
        var aMap: [String: Album] = [:]
        var gMap: [String: [Track]] = [:]
        var arMap: [String: [Track]] = [:]
        var pMap: [String: Track] = [:]

        for t in list {
            pMap[t.source] = t
            if var a = aMap[t.albumKey] {
                if a.artist != t.artist { a.artist = "Artistes divers" }
                a.tracks.append(t)
                if t.added > a.added { a.added = t.added }
                aMap[t.albumKey] = a
            } else {
                order.append(t.albumKey)
                aMap[t.albumKey] = Album(key: t.albumKey, name: t.album, artist: t.artist, added: t.added, tracks: [t])
            }
            gMap[t.genre, default: []].append(t)
            arMap[t.artist, default: []].append(t)
        }

        for k in order {
            if var a = aMap[k] {
                a.tracks.sort { x, y in
                    if x.trackNo != y.trackNo { return x.trackNo < y.trackNo }
                    return x.title.localizedStandardCompare(y.title) == .orderedAscending
                }
                aMap[k] = a
            }
        }

        var aList = order.compactMap { aMap[$0] }
        aList.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return Built(tracks: list, albums: aList, albumMap: aMap, genres: gMap, artists: arMap, paths: pMap)
    }
}
