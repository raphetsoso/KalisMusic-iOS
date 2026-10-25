import SwiftUI
import AVFoundation

/// Logique de l'onglet KalisStore (recherche NCS, écoute, téléchargement, liste de souhaits).
final class StoreModel: ObservableObject {
    struct Failure: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let pageUrl: String
    }

    @Published var query = ""
    @Published var genreId: String? = nil
    @Published var results: [NcsResult] = []
    @Published var status = ""
    /// pageUrl -> "dl:NN" (téléchargement en cours) ou "done"
    @Published var states: [String: String] = [:]
    @Published var wishMode = false
    @Published var genres: [NcsGenre] = Ncs.genres()
    @Published var previewUrl: String?
    @Published var previewLoading = false
    @Published var failure: Failure?

    private var searchToken = 0
    private var previewPlayer: AVPlayer?
    private var previewObs: NSKeyValueObservation?
    private var previewEnd: NSObjectProtocol?
    private var previewWork: DispatchWorkItem?
    private var started = false

    func start() {
        if started { return }
        started = true
        Task {
            try? await Ncs.loadGenres()
            await MainActor.run { self.genres = Ncs.genres() }
        }
        search()
    }

    func search() {
        searchToken += 1
        let token = searchToken
        if wishMode {
            results = StoreData.shared.wishlist
            status = results.isEmpty ? L("Votre liste de souhaits est vide. Touchez l'étoile d'un morceau pour le garder pour plus tard.") : ""
            markAdded()
            return
        }
        status = L("Recherche…")
        let q = query
        let gid = genreId
        Task {
            do {
                let found = try await Ncs.search(q, genreId: gid)
                await MainActor.run {
                    guard token == self.searchToken else { return }
                    self.results = found
                    self.status = found.isEmpty ? L("Aucun résultat") : ""
                    self.markAdded()
                    self.genres = Ncs.genres()
                }
            } catch {
                await MainActor.run {
                    guard token == self.searchToken else { return }
                    self.results = []
                    self.status = L("Recherche impossible : ") + error.localizedDescription
                }
            }
        }
    }

    /// Un morceau supprimé de la bibliothèque doit pouvoir être réinstallé : on oublie ceux dont le fichier a disparu.
    func markAdded() {
        let sd = StoreData.shared
        for (page, file) in sd.addedFiles where !StoreData.fileExists(file) { sd.forget(pageUrl: page) }
        for r in results {
            if let f = sd.addedFiles[r.pageUrl], StoreData.fileExists(f) {
                if states[r.pageUrl] == nil { states[r.pageUrl] = "done" }
            } else if states[r.pageUrl] == "done" {
                states.removeValue(forKey: r.pageUrl)
            }
        }
    }

    func toggleWishMode() {
        wishMode.toggle()
        search()
    }

    // MARK: Téléchargement

    func download(_ r: NcsResult) {
        if states[r.pageUrl] != nil {
            if states[r.pageUrl] == "done" { ToastCenter.shared.show(L("Ce morceau est déjà dans votre bibliothèque")) }
            return
        }
        states[r.pageUrl] = "dl:0"
        var lastPct = -1
        Task {
            do {
                let file = try await Ncs.download(r) { done, total in
                    if total <= 0 { return }
                    let pct = Int(100 * done / total)
                    if pct == lastPct { return }
                    lastPct = pct
                    DispatchQueue.main.async {
                        if self.states[r.pageUrl] != nil { self.states[r.pageUrl] = "dl:\(pct)" }
                    }
                }
                guard case .added(let source) = Importer.importFile(file, move: true) else {
                    throw KError(L("import impossible"))
                }
                // infos du morceau + pochette officielle NCS
                TagStore.shared.putField(source, title: r.title.nilIfEmpty, artist: r.artist.nilIfEmpty,
                                         genre: r.genre.nilIfEmpty)
                if let data = try? await Ncs.downloadCover(r), let jpg = ImageUtil.jpeg(fromData: data) {
                    TagStore.shared.setCover(source, jpegData: jpg)
                }
                await MainActor.run {
                    self.states[r.pageUrl] = "done"
                    StoreData.shared.remember(pageUrl: r.pageUrl, file: source)
                    StoreData.shared.addHistory(title: r.title, artist: r.artist, pageUrl: r.pageUrl, file: source)
                    ToastCenter.shared.show(L("Ajouté à la bibliothèque"))
                    MusicLibrary.shared.refresh()
                }
            } catch {
                await MainActor.run {
                    self.states.removeValue(forKey: r.pageUrl)
                    self.failure = Failure(title: r.title,
                                           message: LF("Échec du téléchargement : %@\n\nVous pouvez aussi télécharger le morceau depuis le site NCS puis l'ajouter avec Importer des morceaux.", error.localizedDescription),
                                           pageUrl: r.pageUrl)
                }
            }
        }
    }

    // MARK: Écoute (aperçu de 30 s)

    func stopPreview() {
        previewWork?.cancel()
        previewWork = nil
        previewPlayer?.pause()
        previewPlayer = nil
        previewObs = nil
        if let e = previewEnd {
            NotificationCenter.default.removeObserver(e)
            previewEnd = nil
        }
        previewUrl = nil
        previewLoading = false
    }

    func togglePreview(_ r: NcsResult) {
        if previewUrl == r.pageUrl {
            stopPreview()
            return
        }
        stopPreview()
        PlayerEngine.shared.pause()
        try? AVAudioSession.sharedInstance().setActive(true)
        previewUrl = r.pageUrl
        previewLoading = true
        let page = r.pageUrl
        Task {
            do {
                let urlString = try await Ncs.streamUrl(r)
                await MainActor.run {
                    guard self.previewUrl == page, let url = URL(string: urlString) else { return }
                    let headers = ["Referer": r.pageUrl.isEmpty ? Ncs.base + "/" : r.pageUrl, "User-Agent": Ncs.ua]
                    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                    let item = AVPlayerItem(asset: asset)
                    let p = AVPlayer(playerItem: item)
                    self.previewPlayer = p
                    self.previewObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
                        DispatchQueue.main.async {
                            guard let self = self, self.previewUrl == page else { return }
                            if it.status == .readyToPlay {
                                self.previewLoading = false
                            } else if it.status == .failed {
                                ToastCenter.shared.show(L("Écoute impossible : ") + (it.error?.localizedDescription ?? L("erreur")))
                                self.stopPreview()
                            }
                        }
                    }
                    self.previewEnd = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                                             queue: .main) { [weak self] _ in
                        self?.stopPreview()
                    }
                    p.play()
                    let work = DispatchWorkItem { [weak self] in
                        if self?.previewUrl == page { self?.stopPreview() }
                    }
                    self.previewWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.show(L("Écoute impossible : ") + error.localizedDescription)
                    if self.previewUrl == page { self.stopPreview() }
                }
            }
        }
    }
}
struct StoreView: View {
    @StateObject private var model = StoreModel()
    @ObservedObject private var data = StoreData.shared
    @EnvironmentObject private var app: AppState

    private var genreName: String {
        if let g = model.genreId, let f = model.genres.first(where: { $0.id == g }) { return f.name }
        return L("Tous")
    }

    private func lineRow(_ label: String, _ value: String, action: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 17)).foregroundColor(.black)
            Spacer()
            Text(value).font(.system(size: 17)).foregroundColor(Theme.gray)
            Icon("ic_chevron_right", size: 22, color: Theme.gray)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .contentShape(Rectangle())
        .overlay(Hairline().padding(.leading, 16), alignment: .bottom)
    }

    var body: some View {
        TabScreen("KalisStore", search: $model.query) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Menu {
                        Button(L("Tous")) { model.genreId = nil }
                        ForEach(model.genres) { g in
                            Button(g.name) { model.genreId = g.id }
                        }
                    } label: {
                        lineRow(L("Genre"), genreName, action: nil)
                    }
                    Button {
                        model.toggleWishMode()
                    } label: {
                        lineRow(model.wishMode ? L("Tout afficher") : L("Liste de souhaits"), "\(data.wishlist.count)", action: nil)
                    }
                    .buttonStyle(RowPressStyle())
                    Text(L("Musique libre d'utilisation de ncs.io. Créditez NCS si vous utilisez un morceau dans vos vidéos."))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.gray)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !model.status.isEmpty {
                        Text(model.status)
                            .font(.system(size: 15))
                            .foregroundColor(Theme.gray)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.results) { r in
                        StoreRow(model: model, r: r)
                    }
                }
            }
            .task { model.start() }
            .onChange(of: model.genreId) { _ in model.search() }
            .onChange(of: model.query) { _ in
                // la recherche se lance après une courte pause de saisie
                let q = model.query
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if q == model.query { model.search() }
                }
            }
            .onDisappear { model.stopPreview() }
            .onChange(of: app.tab) { t in
                if t != 1 { model.stopPreview() }
            }
            .alert(item: $model.failure) { f in
                Alert(title: Text(f.title), message: Text(f.message),
                      primaryButton: .default(Text(L("Ouvrir ncs.io"))) {
                          if let u = URL(string: f.pageUrl.isEmpty ? Ncs.base : f.pageUrl) { UIApplication.shared.open(u) }
                      },
                      secondaryButton: .cancel(Text("OK")))
            }
        }
    }
}

struct StoreRow: View {
    @ObservedObject var model: StoreModel
    let r: NcsResult
    @ObservedObject private var data = StoreData.shared

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                AsyncImage(url: r.coverUrl.flatMap { URL(string: $0) }) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Theme.artBg.overlay(Icon("ic_note", size: 24, color: Theme.accent.opacity(0.45)))
                    }
                }
                .frame(width: 56, height: 56)
                .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.system(size: 18)).foregroundColor(.black).lineLimit(1)
                    Text(r.artist + (r.genre.isEmpty ? "" : " • " + r.genre))
                        .font(.system(size: 15))
                        .foregroundColor(Theme.gray)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.leading, 16)

            Button {
                model.togglePreview(r)
            } label: {
                if model.previewUrl == r.pageUrl && model.previewLoading {
                    ProgressView().frame(width: 40, height: 72)
                } else {
                    Icon(model.previewUrl == r.pageUrl ? "ic_pause" : "ic_play", size: 26, color: Theme.accent)
                        .frame(width: 40, height: 72)
                }
            }
            .buttonStyle(.plain)

            Button {
                model.download(r)
            } label: {
                downloadLabel
            }
            .buttonStyle(.plain)

            Button {
                StoreData.shared.toggleWish(r)
                if model.wishMode { model.search() }
            } label: {
                Icon(data.isWished(r.pageUrl) ? "ic_star_filled" : "ic_star", size: 24, color: Theme.accent)
                    .frame(width: 40, height: 72)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 72)
        .overlay(Hairline().padding(.leading, 86), alignment: .bottom)
    }

    @ViewBuilder
    private var downloadLabel: some View {
        let s = model.states[r.pageUrl]
        if s == "done" {
            Icon("ic_check", size: 26, color: Theme.accent).frame(width: 44, height: 72)
        } else if let s = s, s.hasPrefix("dl:") {
            Text(String(s.dropFirst(3)) + " %")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.accent)
                .frame(width: 44, height: 72)
        } else {
            Icon("ic_import", size: 26, color: Theme.accent).frame(width: 44, height: 72)
        }
    }
}
