import Foundation

/// Un résultat de recherche NoCopyrightSounds (site officiel ncs.io, musique libre d'utilisation, à créditer dans les vidéos).
struct NcsResult: Codable, Identifiable, Hashable {
    var title: String = ""
    var artist: String = ""
    var genre: String = ""
    var pageUrl: String = ""
    var coverUrl: String? = nil
    var downloadUrl: String? = nil
    var id: String { pageUrl }
}

struct NcsGenre: Identifiable {
    var id: String
    var name: String
}

/// Téléchargement avec progression (URLSession en mode délégué).
final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<(URL, HTTPURLResponse), Error>?
    private var session: URLSession!
    private let onProgress: ((Int64, Int64) -> Void)?
    private var savedFile: URL?
    private var saveError: Error?
    private var response: HTTPURLResponse?

    init(progress: ((Int64, Int64) -> Void)?) {
        onProgress = progress
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func download(_ req: URLRequest) async throws -> (URL, HTTPURLResponse) {
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        response = downloadTask.response as? HTTPURLResponse
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            savedFile = dest
        } catch {
            saveError = error
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        guard let cont = continuation else { return }
        continuation = nil
        if let e = error {
            cont.resume(throwing: e)
        } else if let e = saveError {
            cont.resume(throwing: e)
        } else if let f = savedFile, let r = (response ?? (task.response as? HTTPURLResponse)) {
            cont.resume(returning: (f, r))
        } else {
            cont.resume(throwing: KError("téléchargement impossible"))
        }
    }
}

enum Ncs {
    static let base = "https://ncs.io"
    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 KalisMusic/1.0"

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    // MARK: Recherche

    static func search(_ query: String, genreId: String?) async throws -> [NcsResult] {
        let q = query.trimmed
        var out: [NcsResult] = []
        var seen = Set<String>()
        let hasGenre = !(genreId ?? "").isEmpty
        let first: String
        if q.isEmpty && !hasGenre {
            first = base + "/?display=list"               // dernières sorties
        } else {
            var s = base + "/music-search?"
            if hasGenre { s += "genre=" + (genreId ?? "") }
            if !q.isEmpty {
                s += (hasGenre ? "&" : "") + "q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)
            }
            first = s
        }
        for page in 1...2 {
            if out.count >= 40 { break }
            let html: String
            do {
                let url = page == 1 ? first : first + (first.contains("?") ? "&" : "?") + "page=\(page)"
                html = try await get(url)
            } catch {
                if page == 1 { throw error }
                break                       // la 2e page est un bonus : on garde la 1re
            }
            let before = out.count
            parse(html, into: &out, seen: &seen)
            if out.count == before { break }
        }
        return out
    }

    private static func parse(_ html: String, into out: inout [NcsResult], seen: inout Set<String>) {
        harvestGenres(html)
        let linkPattern = #"<a[^>]+href="((?:https?://ncs\.io)?/[A-Za-z0-9_\-]+)"[^>]*>(.*?)</a>"#
        let imgPattern = #"<img[^>]+?(?:data-src|src)="([^"]+)""#
        let dlPattern = #"href="((?:https?://ncs\.io)?/track/download/[0-9a-fA-F\-]+)""#
        let genrePattern = #"<a[^>]+href="[^"]*music-search\?genre=\d+[^"]*"[^>]*>(.*?)</a>"#
        let skip: Set<String> = ["music-search", "music", "track", "artists", "about", "contact"]

        for row in Rx.all(#"<tr[^>]*>(.*?)</tr>"#, in: html) {
            if out.count >= 40 { break }
            let r = row[1]
            var res: NcsResult? = nil
            for l in Rx.all(linkPattern, in: r) {
                let title = clean(l[2])
                let href = abs(l[1])
                if !href.hasPrefix(base + "/") { continue }
                let path = String(href.dropFirst(base.count + 1))
                if title.isEmpty || skip.contains(path) { continue }
                var x = NcsResult()
                x.title = title
                x.pageUrl = href
                // l'artiste est le premier texte qui suit le titre
                var rest = Rx.tail(r, from: l.end)
                rest = Rx.replace(#"<a[^>]+music-search\?genre.*?</a>"#, in: rest, with: " ")
                rest = Rx.replace("<[^>]*>", in: rest, with: "\u{1}")
                for chunk in rest.components(separatedBy: "\u{1}") {
                    let c = clean(chunk)
                    if !c.isEmpty && c.lowercased() != "download" {
                        x.artist = c
                        break
                    }
                }
                res = x
                break
            }
            guard var found = res, !seen.contains(found.pageUrl) else { continue }
            seen.insert(found.pageUrl)
            if let i = Rx.first(imgPattern, in: r) { found.coverUrl = abs(i[1]) }
            if let d = Rx.first(dlPattern, in: r, options: []) { found.downloadUrl = abs(d[1]) }
            if let g = Rx.first(genrePattern, in: r) { found.genre = clean(g[1]) }
            out.append(found)
        }
        if !out.isEmpty { return }

        // Secours : affichage en grille (pas de tableau) -> <a href="/slug"><strong>Titre</strong> Artiste</a>
        let grid = #"<a[^>]+href="((?:https?://ncs\.io)?/[A-Za-z0-9_\-]+)"[^>]*>\s*<strong>(.*?)</strong>(.*?)</a>"#
        for g in Rx.all(grid, in: html) {
            if out.count >= 40 { break }
            var x = NcsResult()
            x.pageUrl = abs(g[1])
            x.title = clean(g[2])
            x.artist = clean(g[3])
            if x.title.isEmpty || seen.contains(x.pageUrl) { continue }
            seen.insert(x.pageUrl)
            out.append(x)
        }
    }

    // MARK: Genres

    /// Genres NCS vérifiés sur le site (nom -> identifiant), utilisés si la liste du site n'est pas lisible.
    private static let baseGenres: [(String, String)] = [
        ("Drum & Bass", "3"), ("House", "10"), ("Melodic Dubstep", "12"), ("Jump-Up", "28"),
        ("Liquid DnB", "29"), ("Neurofunk", "30"), ("Dance-Rock", "38"), ("Garage", "51"),
        ("Progressive House", "55"), ("Complextro", "65"), ("Deep House", "66"),
        ("Tech House", "73"), ("Trance", "81"), ("Witch House", "90")
    ]

    private static let genreQueue = DispatchQueue(label: "kalis.ncs.genres")
    private static var genreMap: [String: String] = {
        var m: [String: String] = [:]
        for (n, i) in baseGenres { m[n] = i }
        return m
    }()

    /// Liste triée de tous les genres connus pour l'instant.
    static func genres() -> [NcsGenre] {
        return genreQueue.sync {
            genreMap.map { NcsGenre(id: $0.value, name: $0.key) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private static func addGenre(_ rawName: String, _ id: String) {
        let name = clean(rawName)
        if name.count < 2 || name.count > 32 || id.count > 3 { return }
        genreQueue.sync { genreMap[name] = id }
    }

    private static func harvestGenres(_ html: String) {
        for m in Rx.all(#"href="[^"]*music-search\?genre=(\d+)[^"]*"[^>]*>(.*?)</a>"#, in: html) {
            addGenre(m[2], m[1])
        }
    }

    /// Lit la liste complète des genres (menu « Search Genres » de la page d'accueil), si possible.
    static func loadGenres() async throws {
        let html = try await get(base + "/")
        harvestGenres(html)
        guard let a = html.range(of: "Search Genres"), let b = html.range(of: "Search Moods"),
              a.upperBound <= b.lowerBound else { return }
        let section = String(html[a.lowerBound..<b.lowerBound])
        let pattern = #"(?:value|data-id|data-value|data-genre|genre=)\s*=?\s*["']?(\d+)["']?[^>]*>\s*(?:<[^>]+>\s*)*([^<>]{2,40})<"#
        for m in Rx.all(pattern, in: section) { addGenre(m[2], m[1]) }
    }

    // MARK: Téléchargement

    /// Télécharge le MP3 dans le dossier de cache et renvoie le fichier. Si le lien de la liste répond 404
    /// (lien périmé), on relit la page du morceau puis on le retrouve par une recherche.
    static func download(_ r: NcsResult, progress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        var last: Error? = nil
        var tried = Set<String>()
        if let d = r.downloadUrl {
            tried.insert(d)
            do { return try await downloadFrom(r, d, progress) } catch { last = error }
        }
        if !r.pageUrl.isEmpty {
            do {
                for d in downloadLinks(try await get(r.pageUrl)) {
                    if !tried.insert(d).inserted { continue }
                    do { return try await downloadFrom(r, d, progress) } catch { last = error }
                }
            } catch {
                if last == nil { last = error }
            }
        }
        // la page n'existe plus à cette adresse : on cherche le morceau sur le site
        do {
            let want = squash(r.title)
            for x in try await search(r.title, genreId: nil) where squash(x.title) == want {
                var links: [String] = []
                if let d = x.downloadUrl { links.append(d) }
                if !x.pageUrl.isEmpty, let html = try? await get(x.pageUrl) { links.append(contentsOf: downloadLinks(html)) }
                for d in links {
                    if !tried.insert(d).inserted { continue }
                    do { return try await downloadFrom(r, d, progress) } catch { last = error }
                }
            }
        } catch {
            if last == nil { last = error }
        }
        throw last ?? KError("lien de téléchargement introuvable sur la page")
    }

    private static func squash(_ s: String) -> String {
        return Rx.replace(#"[^\p{L}\p{N}]"#, in: s.lowercased(), with: "", options: [])
    }

    /// Adresse directe du fichier audio (après les redirections du site), pour l'écouter en streaming sans le télécharger.
    static func streamUrl(_ r: NcsResult) async throws -> String {
        var links: [String] = []
        if let d = r.downloadUrl { links.append(d) }
        var last: Error? = nil
        do {
            if !r.pageUrl.isEmpty {
                for d in downloadLinks(try await get(r.pageUrl)) where !links.contains(d) { links.append(d) }
            }
        } catch {
            last = error
        }
        for d in links {
            do {
                let (bytes, resp) = try await session.bytes(for: try makeRequest(d, referer: r.pageUrl.isEmpty ? base + "/" : r.pageUrl))
                defer { bytes.task.cancel() }
                guard let http = resp as? HTTPURLResponse else { throw KError("réponse invalide") }
                if http.statusCode >= 400 { throw KError("HTTP \(http.statusCode)") }
                let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                if type.hasPrefix("text/") { throw KError("le site demande une validation") }
                return http.url?.absoluteString ?? d
            } catch {
                last = error
            }
        }
        throw last ?? KError("lien introuvable")
    }

    /// Liens de téléchargement d'une page de morceau, les plus fiables d'abord.
    private static func downloadLinks(_ html: String) -> [String] {
        var out: [String] = []
        func add(_ u: String) { let a = abs(u); if !out.contains(a) { out.append(a) } }
        for m in Rx.all(#"href="((?:https?://ncs\.io)?/track/download/[0-9a-fA-F\-]+)""#, in: html, options: []) { add(m[1]) }
        for m in Rx.all(#"href="([^"]+)"[^>]*>\s*(?:<[^>]+>\s*)*download"#, in: html) { add(m[1]) }
        for m in Rx.all(#"href="([^"]+\.mp3[^"]*)""#, in: html) { add(m[1]) }
        return out
    }

    private static func downloadFrom(_ r: NcsResult, _ dl: String, _ progress: @escaping (Int64, Int64) -> Void) async throws -> URL {
        let req = try makeRequest(dl, referer: r.pageUrl.isEmpty ? base + "/" : r.pageUrl)
        let downloader = FileDownloader(progress: progress)
        let (tmp, http) = try await downloader.download(req)
        if http.statusCode >= 400 {
            try? FileManager.default.removeItem(at: tmp)
            throw KError("HTTP \(http.statusCode) sur \(http.url?.absoluteString ?? dl)")
        }
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if type.hasPrefix("text/") {
            try? FileManager.default.removeItem(at: tmp)
            throw KError("le site demande une validation (connexion ou licence)")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: tmp.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        if size < 50 * 1024 {
            try? FileManager.default.removeItem(at: tmp)
            throw KError("fichier reçu trop petit")
        }
        let dir = Paths.caches.appendingPathComponent("ncs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let baseName = (r.artist.isEmpty ? "" : r.artist + " - ") + r.title
        let safe = Rx.replace(#"[\\/:*?"<>|]"#, in: baseName, with: "_", options: []).trimmed
        let dest = dir.appendingPathComponent((safe.isEmpty ? "morceau" : safe) + ".mp3")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    /// Pochette officielle NCS du morceau (image « og:image » de sa page sur ncs.io, sinon la miniature de la liste).
    static func downloadCover(_ r: NcsResult) async throws -> Data {
        var url: String? = nil
        if !r.pageUrl.isEmpty, let html = try? await get(r.pageUrl) {
            let a = #"<meta[^>]+(?:property|name)=["']og:image["'][^>]+content=["']([^"']+)["']"#
            let b = #"<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']og:image["']"#
            if let m = Rx.first(a, in: html) ?? Rx.first(b, in: html) { url = abs(m[1]) }
        }
        if url == nil { url = r.coverUrl }
        guard let u = url else { throw KError("pochette introuvable") }
        let (data, _) = try await session.data(for: try makeRequest(u, referer: base + "/"))
        if data.count < 1024 { throw KError("pochette vide") }
        return data
    }

    // MARK: Réseau

    private static func makeRequest(_ url: String, referer: String) throws -> URLRequest {
        guard let u = URL(string: encodeUrl(url)) else { throw KError("adresse invalide : \(url)") }
        var req = URLRequest(url: u)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(referer, forHTTPHeaderField: "Referer")
        req.setValue("en", forHTTPHeaderField: "Accept-Language")
        req.timeoutInterval = 20
        return req
    }

    static func get(_ url: String) async throws -> String {
        let (data, resp) = try await session.data(for: try makeRequest(url, referer: base + "/"))
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 { throw KError("HTTP \(http.statusCode)") }
        return String(decoding: data, as: UTF8.self)
    }

    /// Encode en %XX les caractères interdits dans une adresse (accents, espaces…) sans toucher aux %XX existants.
    static func encodeUrl(_ u: String) -> String {
        var out = ""
        let forbidden = Array("\"<>\\^`{|}".utf8)
        for b in u.utf8 {
            if b <= 0x20 || b >= 0x7F || forbidden.contains(b) {
                out += String(format: "%%%02X", UInt32(b))
            } else {
                out.append(Character(UnicodeScalar(b)))
            }
        }
        return out
    }

    private static func abs(_ u: String) -> String {
        let s = u.replacingOccurrences(of: "&amp;", with: "&")
        if s.hasPrefix("//") { return "https:" + s }
        if s.hasPrefix("/") { return base + s }
        return s
    }

    private static func clean(_ s: String) -> String {
        var t = Rx.replace("<[^>]*>", in: s, with: " ")
        for (a, b) in [("&amp;", "&"), ("&quot;", "\""), ("&#039;", "'"), ("&#39;", "'"),
                       ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        t = Rx.replace(#"\s+"#, in: t, with: " ", options: [])
        return t.trimmed
    }
}
