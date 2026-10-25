import Foundation

/// Enregistre la webradio en cours d'écoute et ajoute l'enregistrement à la bibliothèque.
final class StreamRecorder: ObservableObject {
    static let shared = StreamRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var source: String?
    private(set) var startedAt = Date()

    private var task: Task<Void, Never>?
    private var stopRequested = false
    private let maxSeconds: TimeInterval = 60 * 60

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

    private func record(_ station: Track) async {
        var tmp: URL? = nil
        var failure: String? = nil
        var savedSource: String? = nil
        var cut = false
        do {
            let r = await StreamResolver.resolve(station.source, name: station.title)
            guard let u = r.url, let url = URL(string: Ncs.encodeUrl(u)) else {
                throw KError(r.error ?? "flux introuvable")
            }
            var req = URLRequest(url: url)
            req.setValue("KalisMusic/1.0", forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 20
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            defer { bytes.task.cancel() }
            let type = ((resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            if type.contains("mpegurl") || url.path.lowercased().hasSuffix(".m3u8") {
                throw KError("Cette station diffuse par segments (HLS) et ne peut pas être enregistrée.")
            }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH.mm"
            let stamp = df.string(from: Date())
            let base = Rx.replace(#"[\\/:*?"<>|]"#, in: station.title + " " + stamp, with: "_", options: [])
            let dir = Paths.caches.appendingPathComponent("rec", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(base + "." + extFor(type))
            tmp = file
            FileManager.default.createFile(atPath: file.path, contents: nil)
            let handle = try FileHandle(forWritingTo: file)
            var buf = Data()
            do {
                for try await b in bytes {
                    buf.append(b)
                    if buf.count >= 16 * 1024 {
                        try handle.write(contentsOf: buf)
                        buf.removeAll(keepingCapacity: true)
                    }
                    if stopRequested || Date().timeIntervalSince(startedAt) > maxSeconds { break }
                }
            } catch is CancellationError {
                // arrêt demandé : on garde ce qui a été reçu
            } catch let e as URLError where e.code == .cancelled {
                // idem
            } catch {
                // connexion perdue en cours de route : on garde ce qui a déjà été reçu
                cut = true
            }
            if !buf.isEmpty { try handle.write(contentsOf: buf) }
            try handle.close()

            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            if size < 20 * 1024 { throw KError(cut ? "Connexion interrompue." : "Enregistrement trop court.") }

            switch Importer.importFile(file, move: true) {
            case .added(let s):
                savedSource = s
            default:
                throw KError("import impossible")
            }
            if let s = savedSource {
                TagStore.shared.putField(s, title: station.title + " – " + stamp, artist: station.title,
                                         album: "Enregistrements radio", genre: "Radio")
            }
        } catch {
            failure = error.localizedDescription
        }
        if let t = tmp { try? FileManager.default.removeItem(at: t) }
        await MainActor.run {
            self.isRecording = false
            self.source = nil
            if savedSource != nil {
                MusicLibrary.shared.refresh()
                ToastCenter.shared.show(cut ? "Connexion interrompue : enregistrement partiel ajouté"
                                            : "Enregistrement ajouté à la bibliothèque")
            } else if let e = failure {
                ToastCenter.shared.show("Enregistrement impossible : " + e)
            }
        }
    }
}
