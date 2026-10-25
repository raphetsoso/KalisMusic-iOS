import SwiftUI
import UIKit
import MediaPlayer
import UniformTypeIdentifiers

// MARK: - Sélecteur de fichiers / dossiers

struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var allowsMultiple = false
    /// true : les fichiers sont copiés dans le dossier temporaire de l'appli (pas d'accès à ouvrir).
    var asCopy = true
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: asCopy)
        vc.allowsMultipleSelection = allowsMultiple
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Pochette (à plat, sans arrondi)

struct ArtView: View {
    let tracks: [Track]
    @ObservedObject private var bus = ArtBus.shared
    @State private var image: UIImage?

    private var taskKey: String {
        return (tracks.first?.source ?? "") + "#\(tracks.count)#\(bus.version)"
    }

    var body: some View {
        Theme.artBg
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                GeometryReader { g in
                    if let img = image {
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: g.size.width, height: g.size.height).clipped()
                    } else {
                        Icon("ic_note", size: max(16, g.size.width * 0.42), color: Theme.accent.opacity(0.45))
                            .frame(width: g.size.width, height: g.size.height)
                    }
                }
            )
            .clipped()
            .task(id: taskKey) {
                image = await ArtLoader.image(forAny: tracks)
            }
    }
}

// MARK: - Mini-lecteur (56 dp)

struct MiniPlayerView: View {
    @ObservedObject private var player = PlayerEngine.shared
    @ObservedObject private var clock = PlaybackClock.shared
    @EnvironmentObject private var app: AppState

    var body: some View {
        if let t = player.current {
            VStack(spacing: 0) {
                Hairline()
                ZStack {
                    VStack(spacing: 1) {
                        Text(t.title).font(.system(size: 15, weight: .semibold)).foregroundColor(.black).lineLimit(1)
                        Text(t.artist).font(.system(size: 13)).foregroundColor(Theme.gray).lineLimit(1)
                    }
                    .padding(.horizontal, 56)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { app.showNowPlaying = true }

                    HStack(spacing: 0) {
                        Button {
                            player.togglePlayPause()
                        } label: {
                            if player.isLoading && player.isPlaying {
                                ProgressView().frame(width: 52, height: 54)
                            } else {
                                Icon(player.isPlaying ? "ic_pause" : "ic_play", size: 28, color: .black)
                                    .frame(width: 52, height: 54)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Menu {
                            Button(L("Morceau suivant")) { player.next() }
                            Button(L("Ouvrir le lecteur")) { app.showNowPlaying = true }
                        } label: {
                            Icon("ic_more", size: 24, color: Theme.accent).frame(width: 52, height: 54)
                        }
                    }
                }
                .frame(height: 54)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.separator)
                        Rectangle().fill(Theme.accent)
                            .frame(width: player.duration > 0 && !t.stream
                                   ? g.size.width * CGFloat(min(1, max(0, clock.position / player.duration))) : 0)
                    }
                }
                .frame(height: 2)
            }
            .background(Theme.miniBg)
        }
    }
}

// MARK: - Menu d'un morceau

final class TrackActions: ObservableObject {
    @Published var editing: Track?
    @Published var addingToPlaylist: Track?
    @Published var deleting: Track?
}

struct TrackMenuItems: View {
    let track: Track
    @ObservedObject var actions: TrackActions
    var playlist: String? = nil
    var position: Int? = nil
    @ObservedObject private var player = PlayerEngine.shared
    @ObservedObject private var playlists = PlaylistStore.shared

    var body: some View {
        Button(L("Lire")) { player.play([track], start: 0, shuffle: false) }
        Button(L("Lire ensuite")) { player.playNext(track) }
        Button(L("Ajouter à la file d'attente")) { player.addToQueue(track) }
        if !track.stream {
            Button(L("Ajouter à une playlist…")) { actions.addingToPlaylist = track }
            Button(playlists.isFavorite(track) ? L("Retirer des favoris") : L("Ajouter aux favoris")) {
                playlists.toggleFavorite(track)
            }
            if let p = playlist, let pos = position {
                Button(L("Retirer de la playlist"), role: .destructive) { playlists.removeAt(p, pos) }
            }
            Button(L("Modifier les infos…")) { actions.editing = track }
            Button(L("Supprimer de l'appareil"), role: .destructive) { actions.deleting = track }
        }
    }
}

/// Ligne de morceau : pochette, titre, sous-titre, bouton « … ».
struct TrackRow: View {
    let track: Track
    var showArt = true
    var subtitle: String? = nil
    @ObservedObject var actions: TrackActions
    var playlist: String? = nil
    var position: Int? = nil
    let onPlay: () -> Void
    @ObservedObject private var player = PlayerEngine.shared

    var body: some View {
        RowShell {
            Button(action: onPlay) {
                RowLabel(art: ArtView(tracks: [track]), title: track.title,
                         sub: subtitle ?? track.artist, highlight: player.current == track)
            }
            .buttonStyle(RowPressStyle())
        } trailing: {
            Menu {
                TrackMenuItems(track: track, actions: actions, playlist: playlist, position: position)
            } label: {
                Icon("ic_more", size: 24, color: Theme.accent).frame(width: 52, height: 72)
            }
        }
    }
}

struct TrackActionHost: ViewModifier {
    @ObservedObject var actions: TrackActions

    func body(content: Content) -> some View {
        content
            .sheet(item: $actions.editing) { t in
                TagEditorView(track: t)
            }
            .sheet(item: $actions.addingToPlaylist) { t in
                PlaylistPicker(track: t)
            }
            .alert(L("Supprimer ce morceau importé de votre appareil ?"),
                   isPresented: Binding(get: { actions.deleting != nil },
                                        set: { if !$0 { actions.deleting = nil } })) {
                Button(L("Supprimer"), role: .destructive) {
                    if let t = actions.deleting { Importer.delete(t) }
                    actions.deleting = nil
                }
                Button(L("Annuler"), role: .cancel) { actions.deleting = nil }
            }
    }
}

extension View {
    func trackActionHost(_ actions: TrackActions) -> some View {
        modifier(TrackActionHost(actions: actions))
    }

    /// Liste « groupée » à angles droits, fond gris iOS.
    func kalisGrouped() -> some View {
        self.listStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.iosBg)
    }
}

// MARK: - Saisie d'un nom (nouvelle playlist…)

struct NamePromptView: View {
    let title: String
    let placeholder: String
    let confirm: String
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(placeholder, text: $text)
                        .autocorrectionDisabled()
                }
            }
            .kalisGrouped()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirm) {
                        let n = text.trimmed
                        if !n.isEmpty { onDone(n) }
                        dismiss()
                    }
                    .disabled(text.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct PlaylistPicker: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var playlists = PlaylistStore.shared
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showNew = true
                    } label: {
                        HStack(spacing: 12) {
                            Icon("ic_add", size: 22, color: Theme.accent)
                            Text(L("Nouvelle playlist…")).foregroundColor(Theme.accent)
                        }
                    }
                }
                Section {
                    ForEach(playlists.names, id: \.self) { n in
                        Button {
                            playlists.add(n, track)
                            ToastCenter.shared.show(LF("Ajouté à « %@ »", n))
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Icon("ic_list", size: 22, color: Theme.accent)
                                Text(n).foregroundColor(.black)
                                Spacer()
                                Text("\(playlists.count(n))").foregroundColor(Theme.gray)
                            }
                        }
                    }
                }
            }
            .kalisGrouped()
            .navigationTitle(L("Ajouter à une playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annuler")) { dismiss() }
                }
            }
            .sheet(isPresented: $showNew) {
                NamePromptView(title: L("Nouvelle playlist"), placeholder: L("Nom de la playlist"), confirm: L("Créer")) { n in
                    if playlists.create(n) {
                        playlists.add(n, track)
                        ToastCenter.shared.show(LF("Ajouté à « %@ »", n))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Divers

struct EmptyStateView: View {
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Icon("ic_note", size: 48, color: Theme.accent.opacity(0.5))
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(message)
                .font(.system(size: 15))
                .foregroundColor(Theme.gray)
                .multilineTextAlignment(.center)
            if let b = buttonTitle, let a = action {
                PinkButton(title: b, action: a)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
