import SwiftUI
import UniformTypeIdentifiers

// MARK: - En lecture (même disposition que l'appli Android : portrait et paysage)

/// Barre de progression : piste fine, curseur rond de 14 dp.
struct ScrubberView: View {
    @ObservedObject private var clock = PlaybackClock.shared
    @ObservedObject private var player = PlayerEngine.shared
    @State private var dragging = false
    @State private var value: Double = 0

    private func track(width w: CGFloat, pos: Double, total: Double) -> some View {
        let frac = CGFloat(min(max(pos / total, 0), 1))
        return ZStack(alignment: .leading) {
            Rectangle().fill(Color(white: 0.78)).frame(height: 3)
            Rectangle().fill(Theme.accent).frame(width: w * frac, height: 3)
            Circle().fill(Theme.accent).frame(width: 14, height: 14)
                .offset(x: w * frac - 7)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    dragging = true
                    value = Double(min(max(v.location.x / w, 0), 1)) * total
                }
                .onEnded { _ in
                    player.seek(to: value)
                    dragging = false
                }
        )
    }

    var body: some View {
        let total = max(player.duration, 1)
        let pos = dragging ? value : min(clock.position, total)
        VStack(spacing: 0) {
            GeometryReader { g in
                track(width: max(g.size.width, 1), pos: pos, total: total)
            }
            .frame(height: 28)
            HStack {
                Text(formatTime(pos))
                Spacer()
                Text("-" + formatTime(max(0, player.duration - pos)))
            }
            .font(.system(size: 12))
            .foregroundColor(Color.black.opacity(0.5))
            .monospacedDigit()
        }
    }
}

struct NowPlayingView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = PlayerEngine.shared
    @ObservedObject private var playlists = PlaylistStore.shared
    @ObservedObject private var recorder = StreamRecorder.shared
    @State private var showQueue = false
    @State private var bgTint: Color = Theme.nowPlayingBg
    @State private var closeTint: Color = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255).opacity(0.7)

    // MARK: couleur de la pochette (comme Android : moyenne mélangée à 82 % de blanc)

    private static func average(_ img: UIImage) -> UIColor? {
        return CoverColor.average(img)
    }

    private func updateTint(_ t: Track) async {
        let img = await ArtLoader.image(forAny: [t])
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                if let img = img, let avg = NowPlayingView.average(img) {
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, al: CGFloat = 0
                    avg.getRed(&r, green: &g, blue: &b, alpha: &al)
                    let w: CGFloat = 0.82
                    bgTint = Color(red: Double(r * (1 - w) + w), green: Double(g * (1 - w) + w), blue: Double(b * (1 - w) + w))
                    var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
                    avg.getHue(&h, saturation: &s, brightness: &v, alpha: &al)
                    closeTint = Color(UIColor(hue: h, saturation: s, brightness: min(v, 0.6), alpha: 0.7))
                } else {
                    bgTint = Theme.nowPlayingBg
                    closeTint = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255).opacity(0.7)
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Icon("ic_chevron_down", size: 24, color: .white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(closeTint))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        GeometryReader { geo in
            let land = geo.size.width > geo.size.height
            let inset = geo.safeAreaInsets
            ZStack(alignment: .topLeading) {
                bgTint
                if let t = player.current {
                    if land {
                        // paysage : pochette carrée pleine hauteur à gauche, panneau à droite (comme layout-land)
                        let side = geo.size.height
                        HStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                ArtView(tracks: [t]).frame(width: side, height: side)
                                closeButton.padding(.leading, 12 + inset.leading).padding(.top, 12)
                            }
                            .frame(width: side + inset.leading, height: side, alignment: .leading)
                            panel(t)
                                .padding(.trailing, inset.trailing)
                                .padding(.top, inset.top)
                                .padding(.bottom, inset.bottom)
                        }
                    } else {
                        // portrait : pochette pleine largeur en haut, panneau en dessous
                        VStack(spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                ArtView(tracks: [t]).frame(width: geo.size.width, height: geo.size.width)
                                closeButton.padding(.leading, 12).padding(.top, 12 + inset.top)
                            }
                            panel(t).padding(.top, 8).padding(.bottom, inset.bottom)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Text("Aucune lecture").foregroundColor(Theme.gray)
                        PinkButton(title: "Fermer") { dismiss() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task(id: player.current?.source ?? "") {
            if let t = player.current { await updateTint(t) }
        }
        .sheet(isPresented: $showQueue) { QueueView() }
    }

    /// Panneau des commandes (identique en portrait et en paysage) : progression, titre, commandes, volume.
    @ViewBuilder
    private func panel(_ t: Track) -> some View {
        VStack(spacing: 0) {
            if t.stream {
                Text(player.isLoading ? "CONNEXION…" : "EN DIRECT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.accent)
                    .frame(height: 42)
            } else {
                ScrubberView()
            }

            Spacer(minLength: 4)

            VStack(spacing: 2) {
                Text(t.title).font(.system(size: 18, weight: .bold)).foregroundColor(.black)
                    .lineLimit(1)
                Text(t.stream ? t.artist : t.artist + " — " + t.album)
                    .font(.system(size: 15)).foregroundColor(Color.black.opacity(0.6)).lineLimit(1)
            }
            .padding(.horizontal, 24)

            if let e = player.errorMessage {
                Text(e)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                Group {
                    if t.stream {
                        Button {
                            if recorder.isRecording { recorder.stop() } else { recorder.start(station: t) }
                        } label: {
                            if recorder.isRecording {
                                VStack(spacing: 0) {
                                    Icon("ic_stop_square", size: 24, color: Color(red: 1, green: 0.23, blue: 0.19))
                                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                                        Text(formatTime(recorder.elapsed) + (recorder.tracksSaved > 0 ? " · \(recorder.tracksSaved)" : "")).font(.system(size: 10)).monospacedDigit()
                                            .foregroundColor(Color(red: 1, green: 0.23, blue: 0.19))
                                    }
                                }
                            } else {
                                Icon("ic_record", size: 24, color: Color.black.opacity(0.8))
                            }
                        }
                    } else {
                        Button {
                            playlists.toggleFavorite(t)
                        } label: {
                            Icon(playlists.isFavorite(t) ? "ic_heart_filled" : "ic_heart", size: 24,
                                 color: playlists.isFavorite(t) ? Theme.accent : Color.black.opacity(0.8))
                        }
                    }
                }
                .frame(width: 44, height: 44)

                Spacer(minLength: 0)

                Button { player.previous() } label: { Icon("ic_rew", size: 36, color: .black) }
                    .frame(width: 56, height: 56)

                Button { player.togglePlayPause() } label: {
                    if player.isLoading && player.isPlaying {
                        ProgressView().frame(width: 72, height: 72)
                    } else {
                        Icon(player.isPlaying ? "ic_pause" : "ic_play", size: 44, color: .black)
                            .frame(width: 72, height: 72)
                    }
                }

                Button { player.next() } label: { Icon("ic_ff", size: 36, color: .black) }
                    .frame(width: 56, height: 56)

                Spacer(minLength: 0)

                Button { showQueue = true } label: { Icon("ic_list", size: 24, color: Color.black.opacity(0.8)) }
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                Icon("ic_volume_low", size: 16, color: Color.black.opacity(0.5)).frame(width: 36, height: 36)
                SystemVolumeSlider().frame(height: 32)
                Icon("ic_volume_high", size: 20, color: Color.black.opacity(0.5)).frame(width: 36, height: 36)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


struct QueueView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var player = PlayerEngine.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("À suivre").font(.system(size: 17, weight: .bold))
                HStack {
                    Spacer()
                    Button("OK") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.accent)
                        .padding(.trailing, 16)
                }
            }
            .frame(height: 52)
            .background(Theme.barBg)
            Hairline()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(player.queue.enumerated()), id: \.offset) { i, t in
                            RowShell {
                                Button {
                                    player.jumpTo(i)
                                } label: {
                                    RowLabel(art: ArtView(tracks: [t]), title: t.title, sub: t.artist,
                                             highlight: i == player.index)
                                }
                                .buttonStyle(RowPressStyle())
                            } trailing: {
                                if i == player.index {
                                    Icon("ic_play", size: 20, color: Theme.accent).frame(width: 44, height: 72)
                                }
                            }
                            .id(i)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(max(player.index, 0), anchor: .center) }
            }
        }
        .background(Color.white)
    }
}

// MARK: - Modifier les infos

struct TagEditorView: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var genre = ""
    @State private var cover: String?          // pochette en attente (chemin relatif)
    @State private var removeCover = false
    @State private var applyToAlbum = false
    @State private var pickingCover = false
    @State private var preview: UIImage?

    init(track: Track) {
        self.track = track
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
        _album = State(initialValue: track.album)
        _genre = State(initialValue: track.genre)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Titre", text: $title)
                    TextField("Artiste", text: $artist)
                    TextField("Album", text: $album)
                    TextField("Genre", text: $genre)
                }
                Section {
                    HStack(spacing: 14) {
                        Group {
                            if let p = preview {
                                Image(uiImage: p).resizable().scaledToFill()
                            } else {
                                ArtView(tracks: [track])
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipped()
                        VStack(alignment: .leading, spacing: 8) {
                            Button("Choisir une pochette…") { pickingCover = true }
                            Button("Retirer la pochette", role: .destructive) {
                                if let c = cover { Paths.deleteCover(c) }
                                cover = nil
                                removeCover = true
                                preview = nil
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    Toggle("Appliquer album, artiste, genre et pochette à tout l'album", isOn: $applyToAlbum)
                        .tint(Theme.accent)
                }
                Section {
                    Button("Rétablir les infos d'origine", role: .destructive) {
                        TagStore.shared.reset(track.source)
                        MusicLibrary.shared.rebuild()
                        ToastCenter.shared.show("Enregistré")
                        dismiss()
                    }
                } footer: {
                    Text("Les infos sont enregistrées dans l'appli (les fichiers ne sont pas modifiés).")
                }
            }
            .kalisGrouped()
            .navigationTitle("Modifier les infos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if let c = cover { Paths.deleteCover(c) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
            .sheet(isPresented: $pickingCover) {
                DocumentPicker(types: [.image], allowsMultiple: false, asCopy: true) { urls in
                    pickingCover = false
                    guard let u = urls.first else { return }
                    if let rel = TagEditorView.importCover(u) {
                        if let old = cover { Paths.deleteCover(old) }
                        cover = rel
                        removeCover = false
                        preview = ImageUtil.thumbnail(fileURL: Paths.url(forCover: rel), maxDim: 300)
                    } else {
                        ToastCenter.shared.show("Impossible d'utiliser cette image")
                    }
                }
            }
        }
    }

    private static func importCover(_ u: URL) -> String? { TagStore.importCover(from: u) }

    private func save() {
        let store = TagStore.shared
        let lib = MusicLibrary.shared
        let targets: [Track] = applyToAlbum ? (lib.album(track.albumKey)?.tracks ?? [track]) : [track]

        for t in targets {
            var o = store.override(for: t.source) ?? TagOverride()
            if t.source == track.source && title.trimmed != track.title {
                o.title = title.trimmed.nilIfEmpty
            }
            if artist.trimmed != track.artist || applyToAlbum { o.artist = artist.trimmed.nilIfEmpty ?? o.artist }
            if album.trimmed != track.album || applyToAlbum { o.album = album.trimmed.nilIfEmpty ?? o.album }
            if genre.trimmed != track.genre || applyToAlbum { o.genre = genre.trimmed.nilIfEmpty ?? o.genre }
            if let c = cover {
                // chaque morceau garde sa propre copie de la pochette
                if t.source == track.source {
                    if o.cover != c { Paths.deleteCover(o.cover) }
                    o.cover = c
                } else if let data = try? Data(contentsOf: Paths.url(forCover: c)) {
                    let rel = "covers/a" + String(UUID().uuidString.prefix(12)) + ".jpg"
                    try? data.write(to: Paths.url(forCover: rel), options: .atomic)
                    Paths.deleteCover(o.cover)
                    o.cover = rel
                }
            } else if removeCover {
                Paths.deleteCover(o.cover)
                o.cover = nil
            }
            store.set(o, for: t.source)
            ArtLoader.invalidate(t.source)
        }
        lib.rebuild()
        ToastCenter.shared.show("Enregistré")
        dismiss()
    }
}

enum CoverColor {
    /// Couleur moyenne d'une image (réduite à 1 pixel), comme ArtLoader.averageColor sur Android.
    static func average(_ img: UIImage) -> UIColor? {
        guard let cg = img.cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space, bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let a = max(CGFloat(px[3]) / 255, 0.001)
        return UIColor(red: min(1, CGFloat(px[0]) / 255 / a), green: min(1, CGFloat(px[1]) / 255 / a),
                       blue: min(1, CGFloat(px[2]) / 255 / a), alpha: 1)
    }
}
