import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var data = StoreData.shared
    @State private var confirmHide = false
    @State private var showAbout = false

    private var versionText: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.1"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Votre compte est local.").foregroundColor(Theme.gray)
                    Text("\(data.installed().count) musiques KalisStore installées")
                        .foregroundColor(Theme.accent)
                }
                Section {
                    NavigationLink("Musiques du KalisStore") { StoreDownloadsView() }
                    NavigationLink("Historique des achats") { StoreHistoryView() }
                    NavigationLink("Statistiques") { StatsView() }
                    NavigationLink("Sauvegarde et restauration") { BackupView() }
                    Button("À propos") { showAbout = true }
                        .foregroundColor(.primary)
                }
                Section {
                    if data.hidden {
                        Button("Réactiver le KalisStore") { data.hidden = false }
                            .foregroundColor(Theme.accent)
                    } else {
                        Button("Retirer le KalisStore de l'interface", role: .destructive) { confirmHide = true }
                    }
                } footer: {
                    Text(data.hidden
                         ? "L'onglet KalisStore est masqué. Vos musiques téléchargées restent sur l'appareil."
                         : "Masque l'onglet KalisStore. Vous pouvez le réactiver ici à tout moment.")
                }
            }
            .listStyle(.grouped)
            .navigationTitle("Compte local")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .alert("Masquer l'onglet KalisStore ? Vous pourrez le réactiver depuis cette page.",
                   isPresented: $confirmHide) {
                Button("Annuler", role: .cancel) {}
                Button("OK") { data.hidden = true }
            }
            .alert("KalisMusic for iOS", isPresented: $showAbout) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Version \(versionText)\nUn lecteur musical inspiré de Musique sur iOS 7 à 9, adapté de KalisMusic for Android.")
            }
        }
    }
}

// MARK: - Musiques installées depuis le KalisStore

struct StoreDownloadsView: View {
    @ObservedObject private var data = StoreData.shared
    @State private var removing: StoreHistoryEntry?

    var body: some View {
        let list = data.installed()
        List {
            Section {
                if list.isEmpty {
                    Text("Aucune musique du KalisStore sur cet appareil.").foregroundColor(Theme.gray)
                }
                ForEach(list) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).lineLimit(1)
                            if !e.artist.isEmpty { Text(e.artist).font(.caption).foregroundColor(Theme.gray) }
                        }
                        Spacer()
                        Button("Retirer", role: .destructive) { removing = e }
                            .buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("Uniquement les musiques téléchargées depuis le KalisStore. Retirer un morceau le supprime de l'appareil ; vous pourrez le retélécharger depuis le store.")
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Musiques du KalisStore")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Retirer cette musique de l'appareil ?",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Annuler", role: .cancel) { removing = nil }
            Button("Retirer", role: .destructive) {
                if let e = removing {
                    if let t = MusicLibrary.shared.byPath(e.file) {
                        Importer.delete(t)
                    } else {
                        try? FileManager.default.removeItem(at: Paths.url(forSource: e.file))
                        MusicLibrary.shared.refresh()
                    }
                    StoreData.shared.forget(pageUrl: e.pageUrl)
                }
                removing = nil
            }
        } message: {
            Text("« \(removing?.title ?? "") »")
        }
    }
}

struct StoreHistoryView: View {
    @ObservedObject private var data = StoreData.shared

    var body: some View {
        let list = data.historyWithState()
        List {
            Section {
                if list.isEmpty {
                    Text("Aucun achat pour l'instant.").foregroundColor(Theme.gray)
                }
                ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.entry.title).lineLimit(1)
                            Text(item.entry.artist + " • " + dateText(item.entry.date))
                                .font(.caption)
                                .foregroundColor(Theme.gray)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.installed ? "Installé" : "Retiré")
                            .font(.footnote)
                            .foregroundColor(item.installed ? Theme.accent : Theme.gray)
                    }
                }
            } footer: {
                Text("Tout ce que vous avez téléchargé depuis le KalisStore, même si retiré depuis.")
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Historique des achats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dateText(_ ms: Double) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}

// MARK: - Statistiques

struct StatsView: View {
    @ObservedObject private var stats = StatsStore.shared
    @State private var confirmReset = false

    var body: some View {
        let d = stats.data
        let tracks = stats.topTracks(10)
        let genres = stats.topGenres(5)
        let artists = stats.topArtists(1)
        List {
            Section {
                row("Temps d'écoute", formatListening(d.totalMs))
                row("Morceaux joués", "\(d.totalPlays)")
                if let t = tracks.first { row("Morceau le plus joué", t.title, "\(t.plays) écoutes") }
                if let g = genres.first {
                    row("Genre préféré", g.title, share(g.ms, d.totalMs))
                }
                if let a = artists.first {
                    row("Artiste préféré", a.title, share(a.ms, d.totalMs))
                }
            } footer: {
                Text("Comptées sur cet appareil pendant la lecture.")
            }
            if !tracks.isEmpty {
                Section {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                        HStack {
                            Text("\(i + 1)").foregroundColor(Theme.gray).frame(width: 24, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).lineLimit(1)
                                Text(t.artist).font(.caption).foregroundColor(Theme.gray).lineLimit(1)
                            }
                            Spacer()
                            Text("\(t.plays) écoutes").font(.footnote).foregroundColor(Theme.gray)
                        }
                    }
                } header: {
                    Text("MORCEAUX LES PLUS JOUÉS")
                }
            }
            if !genres.isEmpty {
                Section {
                    ForEach(Array(genres.enumerated()), id: \.offset) { _, g in
                        HStack {
                            Text(g.title)
                            Spacer()
                            Text(share(g.ms, d.totalMs)).font(.footnote).foregroundColor(Theme.gray)
                        }
                    }
                } header: {
                    Text("GENRES LES PLUS ÉCOUTÉS")
                }
            }
            Section {
                Button("Réinitialiser les statistiques", role: .destructive) { confirmReset = true }
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Statistiques")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Réinitialiser toutes les statistiques d'écoute ?", isPresented: $confirmReset) {
            Button("Non", role: .cancel) {}
            Button("Oui", role: .destructive) { StatsStore.shared.reset() }
        }
    }

    private func share(_ ms: Int64, _ total: Int64) -> String {
        if total <= 0 { return "" }
        return "\(Int(100 * ms / total)) % de votre temps d'écoute"
    }

    private func row(_ label: String, _ value: String, _ sub: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(Theme.gray)
            Text(value).font(.body)
            if !sub.isEmpty { Text(sub).font(.caption).foregroundColor(Theme.accent) }
        }
    }
}

// MARK: - Sauvegarde et restauration

struct BackupView: View {
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var pickRestore = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Text("Enregistrez vos playlists, tags, statistiques et données du KalisStore dans un fichier, puis restaurez-le sur un autre téléphone (iPhone ou Android).")
                    .font(.subheadline)
                    .foregroundColor(Theme.gray)
                Button("Exporter vers un fichier…") { export() }
                Button("Restaurer depuis un fichier…") { pickRestore = true }
            } footer: {
                Text("Le fichier contient : playlists et favoris, tags et pochettes modifiés, statistiques, stations de radio ajoutées, historique et liste de souhaits du KalisStore. Les morceaux eux-mêmes n'y sont pas. Sur le nouveau téléphone, importez d'abord vos morceaux, puis restaurez : chaque morceau est retrouvé par son nom de fichier.")
            }
            if let m = message {
                Section { Text(m).font(.subheadline) }
            }
        }
        .listStyle(.grouped)
        .navigationTitle("Sauvegarde")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let u = exportURL { ShareSheet(items: [u]) }
        }
        .sheet(isPresented: $pickRestore) {
            DocumentPicker(types: [.json, .data], allowsMultiple: false, asCopy: true) { urls in
                pickRestore = false
                guard let u = urls.first else { return }
                restore(u)
            }
        }
    }

    private func export() {
        do {
            let data = try BackupManager.export()
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("KalisMusic-sauvegarde-\(f.string(from: Date())).json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            showShare = true
            message = "Sauvegarde enregistrée"
        } catch {
            message = "Sauvegarde impossible : " + error.localizedDescription
        }
    }

    private func restore(_ url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let s = try BackupManager.restore(data)
            var text = "Restauré : \(s.playlists) playlists, \(s.tags) morceaux modifiés, statistiques : \(s.stats ? "oui" : "non"), \(s.store) entrées du KalisStore."
            if s.missing > 0 {
                text += "\n\(s.missing) morceaux de la sauvegarde sont introuvables sur ce téléphone. Importez-les, puis restaurez à nouveau."
            }
            message = text
        } catch {
            message = error.localizedDescription
        }
    }
}
