import SwiftUI
import UniformTypeIdentifiers

// MARK: - Radio

struct RadioView: View {
    @ObservedObject private var radios = RadioStore.shared
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = PlayerEngine.shared
    @State private var bandIndex = 0
    @State private var showAdd = false
    @State private var coverTarget: String?
    @State private var pickingCover = false
    @State private var deleting: Station?

    private var band: String { bandIndex == 0 ? RadioStore.fm : RadioStore.am }

    var body: some View {
        TabScreen("Radio") {
            let stations = radios.stations(band)
            let queue = RadioStore.tracks(stations)
            ScrollView {
                LazyVStack(spacing: 0) {
                    KSegmented(labels: ["FM", "AM"], selection: $bandIndex)
                        .padding(.vertical, 8)
                    ForEach(Array(stations.enumerated()), id: \.element.id) { i, st in
                        RowShell {
                            Button {
                                player.play(queue, start: i, shuffle: false)
                            } label: {
                                RowLabel(art: ArtView(tracks: [queue[i]]), title: st.name,
                                         sub: st.band + (st.place.isEmpty ? "" : " • " + st.place),
                                         highlight: player.current?.source == st.url)
                            }
                            .buttonStyle(RowPressStyle())
                        } trailing: {
                            if st.custom {
                                Menu {
                                    Button(L("Changer la cover…")) {
                                        coverTarget = st.url
                                        pickingCover = true
                                    }
                                    Button(L("Supprimer"), role: .destructive) { deleting = st }
                                } label: {
                                    Icon("ic_more", size: 24, color: Theme.accent).frame(width: 52, height: 72)
                                }
                            }
                        }
                    }
                    Button {
                        showAdd = true
                    } label: {
                        HStack(spacing: 12) {
                            Icon("ic_add", size: 24, color: Theme.accent)
                            Text(L("Ajouter une station…")).font(.system(size: 18)).foregroundColor(Theme.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                    if !lib.tracks.isEmpty {
                        Hairline().padding(.leading, 16)
                        ShuffleRow(label: LF("Toute ma musique • %ld morceaux", lib.tracks.count)) {
                            player.play(lib.tracks, start: -1, shuffle: true)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAdd) { AddStationView(defaultBand: band) }
        .sheet(isPresented: $pickingCover) {
            DocumentPicker(types: [.image], allowsMultiple: false, asCopy: true) { urls in
                pickingCover = false
                guard let u = urls.first, let target = coverTarget else { return }
                if let rel = TagStore.importCover(from: u) {
                    RadioStore.shared.setCover(url: target, cover: rel)
                } else {
                    ToastCenter.shared.show(L("Impossible d'utiliser cette image"))
                }
            }
        }
        .alert(L("Supprimer cette station ?"), isPresented: Binding(get: { deleting != nil },
                                                                 set: { if !$0 { deleting = nil } })) {
            Button(L("Supprimer"), role: .destructive) {
                if let d = deleting { RadioStore.shared.remove(url: d.url) }
                deleting = nil
            }
            Button(L("Annuler"), role: .cancel) { deleting = nil }
        }
    }
}

struct AddStationView: View {
    let defaultBand: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var isAM: Bool
    @State private var cover: String?
    @State private var pickingCover = false

    init(defaultBand: String) {
        self.defaultBand = defaultBand
        _isAM = State(initialValue: defaultBand == RadioStore.am)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(L("Nom de la station"), text: $name)
                    TextField(L("Site web ou adresse du flux (ex. www.fip.fr)"), text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle(L("Station AM (sinon FM)"), isOn: $isAM)
                        .tint(Theme.accent)
                }
                Section {
                    Button(cover == nil ? L("Choisir une cover…") : L("Changer la cover…")) { pickingCover = true }
                        .foregroundColor(Theme.accent)
                    if cover != nil {
                        Button(L("Retirer la cover"), role: .destructive) {
                            Paths.deleteCover(cover)
                            cover = nil
                        }
                    }
                }
            }
            .kalisGrouped()
            .navigationTitle(L("Ajouter une station"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) {
                        Paths.deleteCover(cover)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Ajouter")) {
                        if name.trimmed.isEmpty || url.trimmed.isEmpty {
                            ToastCenter.shared.show(L("Saisissez un nom et le site web ou l'adresse du flux"))
                            return
                        }
                        let address = StreamResolver.normalize(url)
                        if RadioStore.shared.has(url: address) {
                            ToastCenter.shared.show(L("Cette station existe déjà"))
                            return
                        }
                        RadioStore.shared.add(name: name, url: address,
                                              band: isAM ? RadioStore.am : RadioStore.fm, cover: cover)
                        ArtLoader.clear()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $pickingCover) {
                DocumentPicker(types: [.image], allowsMultiple: false, asCopy: true) { urls in
                    pickingCover = false
                    guard let u = urls.first else { return }
                    if let rel = TagStore.importCover(from: u) {
                        Paths.deleteCover(cover)
                        cover = rel
                    } else {
                        ToastCenter.shared.show(L("Impossible d'utiliser cette image"))
                    }
                }
            }
        }
    }
}

// MARK: - Import

struct ImportView: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @State private var pickFiles = false
    @State private var pickFolder = false
    @State private var busy = false
    @State private var progressText = ""

    private func run(_ urls: [URL], move: Bool) {
        busy = true
        progressText = L("Import…")
        Task {
            let res = await Importer.importAsync(urls, move: move) { done, total, name in
                DispatchQueue.main.async { progressText = LF("Import de %ld sur %ld… %@", done, total, name) }
            }
            await MainActor.run {
                busy = false
                progressText = ""
                ToastCenter.shared.show(LF("%ld ajoutés, %ld ignorés", res.added, res.skipped))
                MusicLibrary.shared.refresh()
            }
        }
    }

    var body: some View {
        TabScreen(L("Import")) {
            List {
                Section {
                    Text(L("Importez vos propres morceaux dans KalisMusic. Les fichiers importés sont copiés dans le dossier Music de l'application et apparaissent aussitôt dans votre bibliothèque."))
                        .font(.subheadline)
                        .foregroundColor(Theme.gray)
                    Text(LF("Votre bibliothèque : %ld morceaux", lib.tracks.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.accent)
                }
                Section {
                    Button { pickFiles = true } label: { Label(L("Importer des morceaux…"), systemImage: "square.and.arrow.down") }
                    Button { pickFolder = true } label: { Label(L("Importer un dossier…"), systemImage: "folder") }
                    Button { MusicLibrary.shared.refresh() } label: { Label(L("Actualiser la bibliothèque"), systemImage: "arrow.clockwise") }
                    if busy || lib.scanning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(busy ? progressText : L("Analyse de votre musique…"))
                                .font(.footnote)
                                .foregroundColor(Theme.gray)
                        }
                    }
                }
                .disabled(busy)
                Section {
                    Text(L("Application Fichiers : ouvrez « Sur mon iPhone » > KalisMusic > Music, copiez-y vos morceaux (MP3, M4A, FLAC, WAV, AIFF), puis touchez Actualiser la bibliothèque."))
                    Text(L("Depuis Windows : avec l'application « Appareils Apple », ouvrez votre iPhone > Partage de fichiers > KalisMusic, et glissez vos fichiers dans le dossier Music."))
                    Text(L("Téléchargements : tout morceau enregistré depuis Safari, Drive ou Dropbox peut être ajouté avec Importer des morceaux…"))
                    Text(L("Jailbreak : avec Filza, copiez simplement les fichiers dans le dossier Documents/Music de l'application."))
                    Text(L("Les formats OGG et WMA ne sont pas lisibles sur iOS."))
                } header: {
                    Text(L("AUTRES FAÇONS D'AJOUTER DE LA MUSIQUE"))
                }
                .font(.footnote)
                .foregroundColor(Theme.gray)
            }
            .listStyle(.grouped)
        }
        .sheet(isPresented: $pickFiles) {
            DocumentPicker(types: [.audio], allowsMultiple: true, asCopy: true) { urls in
                pickFiles = false
                if !urls.isEmpty { run(urls, move: true) }
            }
        }
        .sheet(isPresented: $pickFolder) {
            DocumentPicker(types: [.folder], allowsMultiple: false, asCopy: false) { urls in
                pickFolder = false
                if !urls.isEmpty { run(urls, move: false) }
            }
        }
    }
}
