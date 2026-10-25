import Foundation

/// Sauvegarde / restauration : playlists, favoris, infos modifiées, statistiques, stations ajoutées, données du KalisStore.
/// Les morceaux eux-mêmes n'y sont pas : à la restauration, chaque morceau est retrouvé par son nom de fichier.
/// Le format est le même que celui de KalisMusic for Android.
enum BackupManager {

    struct Summary {
        var playlists = 0
        var tags = 0
        var stats = false
        var store = 0
        var missing = 0
    }

    private static func name(_ path: String) -> String { (path as NSString).lastPathComponent }

    private static func byName() -> [String: String] {
        var m: [String: String] = [:]
        for t in MusicLibrary.shared.tracks where !t.stream { m[name(t.source).lowercased()] = t.source }
        return m
    }

    private static func withNames(_ paths: [String]) -> [[String: Any]] {
        return paths.map { ["path": $0, "name": name($0)] }
    }

    private static func jsonObject<T: Encodable>(_ v: T) -> Any {
        guard let d = try? JSONEncoder().encode(v), let o = try? JSONSerialization.jsonObject(with: d) else { return [:] }
        return o
    }

    // MARK: Export

    static func export() throws -> Data {
        var root: [String: Any] = [:]
        root["app"] = "KalisMusic"
        root["version"] = 1
        root["date"] = Int64(Date().timeIntervalSince1970 * 1000)

        let ps = PlaylistStore.shared
        var lists: [String: Any] = [:]
        for (n, paths) in ps.lists { lists[n] = withNames(paths) }
        root["playlists"] = lists
        root["favorites"] = withNames(ps.favorites)

        var tags: [[String: Any]] = []
        for (source, o) in TagStore.shared.map {
            if !FileManager.default.fileExists(atPath: Paths.url(forSource: source).path) { continue }
            var d: [String: Any] = [:]
            if let v = o.title { d["title"] = v }
            if let v = o.artist { d["artist"] = v }
            if let v = o.album { d["album"] = v }
            if let v = o.genre { d["genre"] = v }
            var item: [String: Any] = ["name": name(source), "tags": d]
            if let c = o.cover, let data = try? Data(contentsOf: Paths.url(forCover: c)) {
                item["cover"] = data.base64EncodedString()
            }
            tags.append(item)
        }
        root["tags"] = tags

        root["stats"] = jsonObject(StatsStore.shared.data)
        root["plays"] = PlayerEngine.shared.playsExport()
        let radios: [[String: Any]] = RadioStore.shared.customs.map { c in
            var o: [String: Any] = ["name": c.name, "url": c.url, "band": c.band]
            if let cv = c.cover, let data = try? Data(contentsOf: Paths.url(forCover: cv)) {
                o["coverData"] = data.base64EncodedString()
            }
            return o
        }
        root["radios"] = radios

        let sd = StoreData.shared
        var store: [String: Any] = [:]
        store["history"] = jsonObject(sd.history)
        store["wishlist"] = jsonObject(sd.wishlist)
        store["added_files"] = sd.addedFiles
        store["hidden"] = sd.hidden
        root["kalisstore"] = store

        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
    }

    // MARK: Restauration

    static func restore(_ data: Data) throws -> Summary {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["app"] as? String) == "KalisMusic" else {
            throw KError(L("Ce fichier n'est pas une sauvegarde KalisMusic."))
        }
        var sum = Summary()
        let names = byName()
        var missing = Set<String>()

        // playlists et favoris : on fusionne avec l'existant
        let ps = PlaylistStore.shared
        var lists = ps.lists
        if let incoming = root["playlists"] as? [String: Any] {
            for (n, v) in incoming {
                var dst = lists[n] ?? []
                merge(&dst, v as? [[String: Any]], names, &missing)
                lists[n] = dst
                sum.playlists += 1
            }
        }
        var fav = ps.favorites
        merge(&fav, root["favorites"] as? [[String: Any]], names, &missing)
        ps.replaceAll(lists: lists, favorites: fav)

        // infos modifiées
        if let tags = root["tags"] as? [[String: Any]] {
            var map = TagStore.shared.map
            for o in tags {
                let fname = (o["name"] as? String) ?? ""
                guard let path = names[fname.lowercased()] else {
                    missing.insert(fname)
                    continue
                }
                let d = (o["tags"] as? [String: Any]) ?? [:]
                var t = TagOverride()
                t.title = d["title"] as? String
                t.artist = d["artist"] as? String
                t.album = d["album"] as? String
                t.genre = d["genre"] as? String
                if let b64 = o["cover"] as? String, let bytes = Data(base64Encoded: b64),
                   let jpg = ImageUtil.jpeg(fromData: bytes) {
                    let rel = "covers/r" + String(UUID().uuidString.prefix(12)) + ".jpg"
                    try? jpg.write(to: Paths.url(forCover: rel), options: .atomic)
                    Paths.deleteCover(map[path]?.cover)
                    t.cover = rel
                } else {
                    t.cover = map[path]?.cover
                }
                map[path] = t
                sum.tags += 1
            }
            TagStore.shared.replaceAll(map)
            ArtLoader.clear()
        }

        // statistiques et compteurs d'écoutes
        if let s = root["stats"], JSONSerialization.isValidJSONObject(s),
           let d = try? JSONSerialization.data(withJSONObject: s),
           let stats = try? JSONDecoder().decode(StatsData.self, from: d) {
            StatsStore.shared.restore(stats, byName: names)
            sum.stats = true
        }
        if let plays = root["plays"] as? [String: Any] {
            var out: [String: Int] = [:]
            for (k, v) in plays {
                if let n = v as? Int { out[k] = n } else if let n = (v as? NSNumber)?.intValue { out[k] = n }
            }
            PlayerEngine.shared.playsRestore(out, byName: names)
        }

        // stations ajoutées : on fusionne par adresse
        if let radios = root["radios"] as? [[String: Any]] {
            var mine = RadioStore.shared.customs
            var urls = Set(mine.map { $0.url })
            for r in radios {
                guard let url = r["url"] as? String, let n = r["name"] as? String, !urls.contains(url) else { continue }
                urls.insert(url)
                var cover: String? = nil
                if let b64 = r["coverData"] as? String, let bytes = Data(base64Encoded: b64),
                   let jpg = ImageUtil.jpeg(fromData: bytes) {
                    let rel = "covers/s" + String(UUID().uuidString.prefix(12)) + ".jpg"
                    try? jpg.write(to: Paths.url(forCover: rel), options: .atomic)
                    cover = rel
                }
                mine.append(CustomStation(name: n, url: url, band: (r["band"] as? String) ?? RadioStore.fm, cover: cover))
            }
            RadioStore.shared.replaceCustoms(mine)
        }

        // KalisStore
        if let store = root["kalisstore"] as? [String: Any] {
            var hist: [StoreHistoryEntry] = []
            if let h = store["history"], JSONSerialization.isValidJSONObject(h),
               let d = try? JSONSerialization.data(withJSONObject: h),
               let list = try? JSONDecoder().decode([StoreHistoryEntry].self, from: d) {
                hist = list.map { e in
                    var x = e
                    if !x.file.isEmpty, let p = names[name(x.file).lowercased()] { x.file = p }
                    return x
                }
                sum.store += hist.count
            }
            var wish: [NcsResult] = []
            if let w = store["wishlist"], JSONSerialization.isValidJSONObject(w),
               let d = try? JSONSerialization.data(withJSONObject: w),
               let list = try? JSONDecoder().decode([NcsResult].self, from: d) {
                wish = list
            }
            var added: [String: String] = [:]
            if let a = store["added_files"] as? [String: String] {
                for (k, v) in a { added[k] = names[name(v).lowercased()] ?? v }
            }
            StoreData.shared.replace(history: hist, wishlist: wish, added: added,
                                     hidden: (store["hidden"] as? Bool) ?? false)
        }

        sum.missing = missing.count
        MusicLibrary.shared.refresh()
        return sum
    }

    /// Ajoute à dst les morceaux de src (chemin retrouvé par nom de fichier), sans doublon.
    private static func merge(_ dst: inout [String], _ src: [[String: Any]]?, _ names: [String: String], _ missing: inout Set<String>) {
        guard let src = src else { return }
        for o in src {
            let fname = (o["name"] as? String) ?? ""
            var path = names[fname.lowercased()]
            if path == nil {
                missing.insert(fname)
                path = (o["path"] as? String) ?? ""
            }
            if let p = path, !p.isEmpty, !dst.contains(p) { dst.append(p) }
        }
    }
}
