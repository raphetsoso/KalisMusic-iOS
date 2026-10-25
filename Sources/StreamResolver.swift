import Foundation

/// Trouve le vrai flux audio derrière une adresse de webradio avant de la donner au lecteur.
///  - flux direct (mp3, aac, Shoutcast/Icecast) : utilisé tel quel ;
///  - liste de lecture (.pls, .m3u) : on prend le premier flux valide ;
///  - page web (« https://www.fip.fr ») : on cherche le flux dans la page ;
///  - en dernier recours : annuaire public radio-browser.info, par nom de station / nom de site.
/// Si tout échoue, l'adresse d'origine est renvoyée telle quelle : AVPlayer lit nativement Shoutcast/Icecast.
enum StreamResolver {

    struct Result {
        var url: String?
        var error: String?
    }

    private static let ua = "KalisMusic/1.0"
    private static let maxDepth = 2
    private static let maxCandidates = 6
    private static let maxBody = 512 * 1024

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        return URLSession(configuration: c)
    }()

    static func normalize(_ u: String) -> String {
        let t = u.trimmed
        if t.isEmpty { return t }
        let low = t.lowercased()
        if low.hasPrefix("http://") || low.hasPrefix("https://") { return t }
        if low.hasPrefix("//") { return "https:" + t }
        return "https://" + t
    }

    static func resolve(_ url: String, name: String?) async -> Result {
        let start = normalize(url)
        var lastError: String? = nil
        do {
            let u = try await discover(start, depth: 0)
            return Result(url: u, error: nil)
        } catch {
            lastError = error.localizedDescription
        }
        if let found = try? await fromDirectory(name: name, host: hostOf(start)) {
            return Result(url: found, error: nil)
        }
        return Result(url: start, error: lastError)
    }

    // MARK: Découverte

    private static func discover(_ url: String, depth: Int) async throws -> String {
        var candidates = [url]
        if url.hasPrefix("https://") { candidates.append("http://" + String(url.dropFirst(8))) }
        var last: Error? = nil
        for c in candidates {
            do { return try await probe(c, depth: depth) } catch { last = error }
        }
        throw last ?? KError("adresse invalide")
    }

    private static func request(_ url: String) throws -> URLRequest {
        guard let u = URL(string: Ncs.encodeUrl(url)) else { throw KError("adresse invalide") }
        var req = URLRequest(url: u)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        return req
    }

    private static func probe(_ url: String, depth: Int) async throws -> String {
        let (bytes, resp) = try await session.bytes(for: try request(url))
        defer { bytes.task.cancel() }
        guard let http = resp as? HTTPURLResponse else { throw KError("réponse invalide") }
        if http.statusCode >= 400 { throw KError("HTTP \(http.statusCode)") }

        let finalURL = http.url?.absoluteString ?? url
        let path = (http.url?.path ?? "").lowercased()
        var type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if let semi = type.firstIndex(of: ";") { type = String(type[type.startIndex..<semi]) }
        type = type.trimmed

        var icy = false
        for (k, _) in http.allHeaderFields where String(describing: k).lowercased().hasPrefix("icy-") {
            icy = true
            break
        }
        if icy { return finalURL }

        let playlistName = path.hasSuffix(".pls") || path.hasSuffix(".m3u") || path.hasSuffix(".m3u8") || path.hasSuffix(".asx")
        let hls = (type.contains("mpegurl") && type != "audio/x-mpegurl" && type != "audio/mpegurl") || path.hasSuffix(".m3u8")
        let playlist = type.contains("mpegurl") || type.contains("scpls") || type.contains("pls+xml") || playlistName
        let text = type.hasPrefix("text/") || type.contains("html") || type.contains("xml") || type.contains("json")

        if !playlist && !text {
            // audio, ogg, flux binaire… : on le laisse au lecteur
            return finalURL
        }

        var data = Data()
        for try await b in bytes {
            data.append(b)
            if data.count >= maxBody { break }
        }
        let body = String(decoding: data, as: UTF8.self)

        if body.contains("#EXT-X-") { return finalURL }          // HLS : AVPlayer sait le lire
        if hls && body.isEmpty { return finalURL }

        if playlist || body.hasPrefix("[playlist]") || body.hasPrefix("#EXTM3U") {
            let entries = playlistEntries(body, base: finalURL)
            if depth >= maxDepth { throw KError("liste de lecture trop imbriquée") }
            var last: Error? = nil
            var n = 0
            for e in entries {
                if n >= maxCandidates { break }
                n += 1
                do { return try await discover(e, depth: depth + 1) } catch { last = error }
            }
            throw last ?? KError("liste de lecture vide")
        }

        // page web : on cherche le flux dans le code de la page
        if depth >= maxDepth { throw KError("aucun flux audio trouvé sur la page") }
        let found = streamsInPage(body, base: finalURL)
        var last: Error? = nil
        var n = 0
        for c in found {
            if n >= maxCandidates { break }
            n += 1
            do { return try await discover(c, depth: depth + 1) } catch { last = error }
        }
        throw KError("aucun flux audio trouvé sur cette page web" + (last == nil ? "" : " (\(last!.localizedDescription))"))
    }

    // MARK: Analyse de page

    private static let extURL = #"https?:(?:\\?/){2}[^\s"'<>()]+?\.(?:mp3|aac|m3u8|m3u|pls|ogg|opus|aacp)(?:\?[^\s"'<>()]*)?"#
    private static let tagSrc = #"<(?:audio|source|embed|meta)[^>]+?(?:src|content|data-src|data-url|data-stream)\s*=\s*["']([^"']+)["'][^>]*>"#
    private static let streamish = #"https?:(?:\\?/){2}[^\s"'<>()\\]*(?:icecast|shoutcast|/stream|/live|streaming|/listen|:8\d{3}/)[^\s"'<>()\\]*"#

    static func streamsInPage(_ html: String, base: String) -> [String] {
        var out: [String] = []
        func add(_ raw: String) {
            if let u = absolute(raw, base: base), !out.contains(u) { out.append(u) }
        }
        for m in Rx.all(tagSrc, in: html) {
            let tag = m[0].lowercased()
            let v = m[1]
            if tag.hasPrefix("<meta") && !(tag.contains("og:audio") || tag.contains("twitter:player:stream")) { continue }
            if looksVisual(v) { continue }
            add(v)
        }
        for m in Rx.all(extURL, in: html) { add(m[0]) }
        for m in Rx.all(streamish, in: html) { add(m[0]) }
        return out
    }

    private static func looksVisual(_ v: String) -> Bool {
        let l = v.lowercased()
        return [".jpg", ".png", ".gif", ".webp", ".css", ".js", ".svg", ".mp4"].contains { l.hasSuffix($0) }
    }

    private static func absolute(_ raw: String, base: String) -> String? {
        var u = raw.replacingOccurrences(of: "\\/", with: "/")
        u = u.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "\\u0026", with: "&").trimmed
        if u.isEmpty || u.hasPrefix("data:") || u.hasPrefix("javascript:") { return nil }
        guard let b = URL(string: base), let abs = URL(string: u, relativeTo: b)?.absoluteURL else { return nil }
        let s = abs.absoluteString
        if looksVisual(s) { return nil }
        if abs.path.count <= 1 { return nil }       // simple nom de domaine : pas un flux
        return s
    }

    /// Entrées d'un .pls ou d'un .m3u (adresses absolues).
    static func playlistEntries(_ body: String, base: String) -> [String] {
        var out: [String] = []
        for line in body.components(separatedBy: .newlines) {
            let l = line.trimmed
            if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("[") { continue }
            var v: String? = nil
            if l.lowercased().hasPrefix("file"), let eq = l.firstIndex(of: "=") {
                v = String(l[l.index(after: eq)...]).trimmed
            } else if !l.contains("=") || l.hasPrefix("http") {
                v = l
            }
            guard let value = v, !value.isEmpty else { continue }
            if let abs = absolute(value, base: base) { out.append(abs) }
        }
        return out
    }

    // MARK: Annuaire (secours)

    private static let directories = [
        "https://de1.api.radio-browser.info", "https://de2.api.radio-browser.info",
        "https://nl1.api.radio-browser.info", "https://at1.api.radio-browser.info"
    ]

    private static func hostOf(_ url: String) -> String {
        guard let h = URL(string: url)?.host?.lowercased() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    private static func norm(_ s: String) -> String {
        return Rx.replace("[^a-z0-9]", in: s.lowercased(), with: "", options: [])
    }

    /// Cherche la station dans radio-browser.info : par son nom, en privilégiant celle dont le site correspond.
    private static func fromDirectory(name: String?, host: String) async throws -> String? {
        var label = (name ?? "").trimmed
        if label.isEmpty && !host.isEmpty { label = host.components(separatedBy: ".").first ?? "" }
        if label.isEmpty { return nil }
        guard let q = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let path = "/json/stations/search?hidebroken=true&order=clickcount&reverse=true&limit=40&name=" + q
        var last: Error? = nil
        for dir in directories {
            do {
                var req = URLRequest(url: URL(string: dir + path)!)
                req.setValue(ua, forHTTPHeaderField: "User-Agent")
                let (data, _) = try await session.data(for: req)
                guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
                let wantName = norm(label)
                var best: String? = nil
                var bestLoose: String? = nil
                for o in arr {
                    var u = (o["url_resolved"] as? String) ?? ""
                    if u.isEmpty { u = (o["url"] as? String) ?? "" }
                    if u.isEmpty { continue }
                    let hostMatch = !host.isEmpty && hostOf((o["homepage"] as? String) ?? "") == host
                    let nameMatch = norm((o["name"] as? String) ?? "") == wantName
                    if hostMatch && best == nil { best = u }
                    if nameMatch && bestLoose == nil { bestLoose = u }
                    if hostMatch { break }
                }
                var pick = best ?? bestLoose
                if pick == nil, host.isEmpty, let first = arr.first {
                    let u = (first["url_resolved"] as? String) ?? ""
                    if !u.isEmpty { pick = u }
                }
                guard let chosen = pick else { return nil }
                return try await discover(chosen, depth: maxDepth - 1)
            } catch {
                last = error
            }
        }
        if let l = last { throw l }
        return nil
    }
}
