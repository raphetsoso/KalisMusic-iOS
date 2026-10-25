import Foundation

/// Enregistre la webradio en cours d'écoute.
///  - si la station envoie les titres en cours (métadonnées ICY), chaque morceau est coupé au changement de titre,
///    nommé, étiqueté (titre, artiste) et habillé de sa pochette, puis ajouté à la bibliothèque ;
///    le premier et le dernier morceau, incomplets, sont écartés ;
///  - sinon, l'enregistrement complet est ajouté en un seul fichier.
final class StreamRecorder: ObservableObject {
    static let shared = StreamRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var source: String?
    /// Nombre de morceaux déjà ajoutés pendant cet enregistrement.
    @Published private(set) var tracksSaved = 0
    private(set) var startedAt = Date()

    private var task: Task<Void, Never>?
    private var stopRequested = false
    private let maxSeconds: TimeInterval = 3 * 60 * 60
    private let minTrackSeconds: TimeInterval = 40

    private init() {}

    var elapsed: TimeInterval { isRecording ? Date().timeIntervalSince(startedAt) : 0 }

    func stop() {
        stopRequested = true
        task?.cancel()
    }

    func start(station: Track) {
        guard !isRecording, station.stream else { return }
        isRecording = true
        stopRequested = false
        startedAt = Date()
        source = station.source
        tracksSaved = 0
        task = Task.detached { [weak self] in
            await self?.record(station)
        }
    }

    /// Appelé quand on change de station : l'enregistrement s'arrête là.
    func playbackChanged(current: Track?) {
        if isRecording, current == nil || current?.stream != true || current?.source != source { stop() }
    }

    private func extFor(_ type: String) -> String {
        if type.contains("aac") { return "aac" }
        if type.contains("mp4") || type.contains("m4a") { return "m4a" }
        if type.contains("flac") { return "flac" }
        return "mp3"
    }

    // MARK: Fichier en cours d'écriture

    private final class Segment {
        let url: URL
        let handle: FileHandle
        var buf = Data()
        var bytes = 0
        let started = Date()
        var title: String?

        init?(dir: URL, ext: String, title: String?) {
            let u = dir.appendingPathComponent("seg-" + String(UUID().uuidString.prefix(10)) + "." + ext)
            FileManager.default.createFile(atPath: u.path, contents: nil)
            guard let h = try? FileHandle(forWritingTo: u) else { return nil }
            url = u
            handle = h
            self.title = title
        }

        func append(_ b: UInt8) {
            buf.append(b)
            bytes += 1
            if buf.count >= 16 * 1024 { flush() }
        }

        func flush() {
            if buf.isEmpty { return }
            try? handle.write(contentsOf: buf)
            buf.removeAll(keepingCapacity: true)
        }

        func close() {
            flush()
            try? handle.close()
        }

        var seconds: TimeInterval { Date().timeIntervalSince(started) }
    }

    // MARK: Analyse des métadonnées ICY

    private static func streamTitle(_ meta: Data) -> String? {
        let text = String(decoding: meta, as: UTF8.self)
        let s = text.contains("\u{FFFD}") ? (String(data: meta, encoding: .isoLatin1) ?? text) : text
        guard let m = Rx.first(#"StreamTitle='(.*?)';"#, in: s) else { return nil }
        let t = m[1].trimmed
        return t.isEmpty ? nil : t
    }

    private static func splitTitle(_ full: String) -> (artist: String?, title: String) {
        for sep in [" - ", " – ", " — "] {
            if let r = full.range(of: sep) {
                let a = String(full[full.startIndex..<r.lowerBound]).trimmed
                let t = String(full[r.upperBound...]).trimmed
                if !a.isEmpty && !t.isEmpty { return (a, t) }
            }
        }
        return (nil, full)
    }

    // MARK: Pochette (recherche iTunes, gratuite, sans clé)

    private static func norm(_ s: String) -> String {
        return Rx.replace("[^a-z0-9]", in: s.lowercased(), with: "", options: [])
    }

    private struct Hit {
        var album: String?
        var genre: String?
        var cover: Data?
    }

    /// Cherche le morceau sur iTunes pour en tirer l'album, le genre et la pochette (le titre et l'artiste restent ceux de la radio).
    private static func lookup(artist: String?, title: String) async -> Hit? {
        let term = ((artist ?? "") + " " + title).trimmed
        guard let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?media=music&entity=song&limit=5&term=" + q) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]] else { return nil }
        let wantTitle = norm(title)
        let wantArtist = norm(artist ?? "")
        let tKey = String(wantTitle.prefix(6))
        let aKey = String(wantArtist.prefix(4))
        if tKey.isEmpty { return nil }
        for r in results {
            let name = norm((r["trackName"] as? String) ?? "")
            let who = norm((r["artistName"] as? String) ?? "")
            let titleOK = name.contains(tKey) || wantTitle.contains(String(name.prefix(6)))
            let artistOK = aKey.isEmpty || who.contains(aKey) || wantArtist.contains(String(who.prefix(4)))
            if !(titleOK && artistOK) { continue }
            var hit = Hit()
            if let album = r["collectionName"] as? String, !album.trimmed.isEmpty { hit.album = album }
            if let g = r["primaryGenreName"] as? String, !g.trimmed.isEmpty { hit.genre = g }
            if let art = r["artworkUrl100"] as? String,
               let u = URL(string: art.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
               let (img, _) = try? await URLSession.shared.data(from: u) {
                hit.cover = img
            }
            return hit
        }
        return nil
    }

    /// Logo de la station (celui affiché dans la liste Radio), utilisé quand aucune pochette n'est trouvée.
    private static func stationCover(_ station: Track) async -> Data? {
        guard let img = await ArtLoader.image(forAny: [station]) else { return nil }
        return img.jpegData(compressionQuality: 0.9)
    }

    // MARK: Ajout d'un morceau découpé à la bibliothèque

    private func saveTrack(file: URL, full: String, station: Track) async {
        let (artist, title) = StreamRecorder.splitTitle(full)
        let nice = Rx.replace(#"[\\/:*?"<>|]"#, in: full, with: "_", options: []).trimmed
        let named = file.deletingLastPathComponent().appendingPathComponent(nice + "." + file.pathExtension)
        var use = file
        if (try? FileManager.default.moveItem(at: file, to: named)) != nil { use = named }
        guard case .added(let s) = Importer.importFile(use, move: true) else {
            try? FileManager.default.removeItem(at: use)
            return
        }
        let hit = await StreamRecorder.lookup(artist: artist, title: title)
        TagStore.shared.putField(s, title: title, artist: artist ?? station.title,
                                 album: hit?.album ?? station.title, genre: hit?.genre ?? "Radio")
        if let data = hit?.cover, let jpg = ImageUtil.jpeg(fromData: data) {
            TagStore.shared.setCover(s, jpegData: jpg)
        } else if let data = await StreamRecorder.stationCover(station) {
            TagStore.shared.setCover(s, jpegData: data)
        }
        await MainActor.run {
            self.tracksSaved += 1
            MusicLibrary.shared.refresh()
        }
    }

    // MARK: Enregistrement

    private func record(_ station: Track) async {
        var failure: String? = nil
        var cut = false
        var singleSaved = false
        var noTitles = false
        var partialOnly = false
        var savers: [Task<Void, Never>] = []
        var cuts = 0
        var seg: Segment? = nil
        let dir = Paths.caches.appendingPathComponent("rec", isDirectory: true)
        do {
            let r = await StreamResolver.resolve(station.source, name: station.title)
            guard let u = r.url, let url = URL(string: Ncs.encodeUrl(u)) else {
                throw KError(r.error ?? L("flux introuvable"))
            }
            var req = URLRequest(url: url)
            req.setValue("KalisMusic/1.0", forHTTPHeaderField: "User-Agent")
            req.setValue("1", forHTTPHeaderField: "Icy-MetaData")
            req.timeoutInterval = 20
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            defer { bytes.task.cancel() }
            let http = resp as? HTTPURLResponse
            let type = (http?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if type.contains("mpegurl") || url.path.lowercased().hasSuffix(".m3u8") {
                throw KError(L("Cette station diffuse par segments (HLS) et ne peut pas être enregistrée."))
            }
            let metaint = Int(http?.value(forHTTPHeaderField: "icy-metaint") ?? "") ?? 0
            let ext = extFor(type)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let first = Segment(dir: dir, ext: ext, title: nil) else { throw KError(L("fichier temporaire impossible")) }
            seg = first

            var state = 0                 // 0 audio, 1 octet de longueur, 2 métadonnées
            var audioLeft = metaint
            var metaLeft = 0
            var meta = Data()
            var current: String? = nil    // titre en cours
            var firstIsPartial = true     // le segment initial commence au milieu d'un morceau

            func titleChanged(_ newTitle: String) {
                guard let s = seg else { return }
                if current == nil {
                    // premier titre reçu : c'est celui du morceau en cours (déjà commencé)
                    current = newTitle
                    s.title = newTitle
                    return
                }
                if newTitle == current { return }
                // nouveau morceau : on ferme le précédent
                cuts += 1
                s.close()
                let done = s
                let doneTitle = current
                let partial = firstIsPartial
                firstIsPartial = false
                if !partial, let t = doneTitle, done.seconds >= minTrackSeconds, done.bytes > 200 * 1024 {
                    savers.append(Task { [weak self] in
                        await self?.saveTrack(file: done.url, full: t, station: station)
                    })
                } else {
                    try? FileManager.default.removeItem(at: done.url)
                }
                current = newTitle
                seg = Segment(dir: dir, ext: ext, title: newTitle)
            }

            do {
                for try await b in bytes {
                    if metaint <= 0 {
                        seg?.append(b)
                        // pas de métadonnées dans le flux : on suit le titre annoncé au lecteur
                        if let sg = seg, sg.bytes % 8192 == 0, let live = PlayerEngine.shared.liveTitle {
                            titleChanged(live)
                        }
                    } else {
                        switch state {
                        case 0:
                            seg?.append(b)
                            audioLeft -= 1
                            if audioLeft == 0 { state = 1 }
                        case 1:
                            metaLeft = Int(b) * 16
                            if metaLeft == 0 { state = 0; audioLeft = metaint } else { state = 2; meta.removeAll(keepingCapacity: true) }
                        default:
                            meta.append(b)
                            metaLeft -= 1
                            if metaLeft == 0 {
                                state = 0
                                audioLeft = metaint
                                if let t = StreamRecorder.streamTitle(meta) { titleChanged(t) }
                            }
                        }
                    }
                    if stopRequested || Date().timeIntervalSince(startedAt) > maxSeconds { break }
                }
            } catch is CancellationError {
                // arrêt demandé
            } catch let e as URLError where e.code == .cancelled {
                // idem
            } catch {
                cut = true
            }

            // fin : le dernier morceau est incomplet. Sans aucun changement de titre, on garde tout en un fichier.
            if let s = seg {
                s.close()
                seg = nil
                if cuts == 0, let t = current, s.bytes >= 20 * 1024 {
                    // la station envoie ses titres mais le titre n'a pas changé : un seul morceau, incomplet
                    await saveTrack(file: s.url, full: t, station: station)
                    partialOnly = true
                } else if cuts == 0 {
                    if s.bytes >= 20 * 1024 {
                        noTitles = true
                        let df = DateFormatter()
                        df.dateFormat = "yyyy-MM-dd HH.mm"
                        let stamp = df.string(from: Date())
                        let label = station.title + " – " + stamp
                        let named = dir.appendingPathComponent(
                            Rx.replace(#"[\\/:*?"<>|]"#, in: label, with: "_", options: []) + "." + ext)
                        try? FileManager.default.moveItem(at: s.url, to: named)
                        if case .added(let src) = Importer.importFile(FileManager.default.fileExists(atPath: named.path) ? named : s.url, move: true) {
                            TagStore.shared.putField(src, title: label, artist: station.title,
                                                     album: station.title, genre: "Radio")
                            if let data = await StreamRecorder.stationCover(station) {
                                TagStore.shared.setCover(src, jpegData: data)
                            }
                            singleSaved = true
                        }
                    } else {
                        try? FileManager.default.removeItem(at: s.url)
                        throw KError(cut ? L("Connexion interrompue.") : L("Enregistrement trop court."))
                    }
                } else {
                    try? FileManager.default.removeItem(at: s.url)
                }
            }
        } catch {
            failure = error.localizedDescription
            if let s = seg {
                s.close()
                try? FileManager.default.removeItem(at: s.url)
            }
        }
        for t in savers { await t.value }
        let count = await MainActor.run { self.tracksSaved }
        await MainActor.run {
            self.isRecording = false
            self.source = nil
            MusicLibrary.shared.refresh()
            if partialOnly {
                ToastCenter.shared.show(L("Un seul morceau enregistré, incomplet : le titre n'a pas changé. Laissez tourner plus longtemps pour découper."))
            } else if singleSaved && noTitles {
                ToastCenter.shared.show(L("Cette station n'envoie pas les titres : enregistrement en un seul fichier."))
            } else if count > 0 {
                ToastCenter.shared.show(LF(count > 1 ? "%ld morceaux ajoutés à la bibliothèque" : "%ld morceau ajouté à la bibliothèque", count))
            } else if singleSaved {
                ToastCenter.shared.show(cut ? L("Connexion interrompue : enregistrement partiel ajouté")
                                            : L("Enregistrement ajouté à la bibliothèque"))
            } else if let e = failure {
                ToastCenter.shared.show(L("Enregistrement impossible : ") + e)
            } else {
                ToastCenter.shared.show(L("Aucun morceau complet enregistré (restez plus longtemps sur la station)"))
            }
        }
    }
}
