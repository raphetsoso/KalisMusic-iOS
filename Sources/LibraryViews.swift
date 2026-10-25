import SwiftUI

// MARK: - Liste de morceaux (album, genre, artiste, playlist…)

enum ListSource {
    case album(String)
    case genre(String)
    case artist(String)
    case songs
    case playlist(String)
    case favorites
    case fixed(String, [Track])
}

struct SongListView: View {
    let source: ListSource
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var playlists = PlaylistStore.shared
    @ObservedObject private var player = PlayerEngine.shared
    @StateObject private var actions = TrackActions()
    @State private var query = ""

    private var title: String {
        switch source {
        case .album(let k): return lib.album(k)?.name ?? "Album"
        case .genre(let n): return n
        case .artist(let n): return n
        case .songs: return "Morceaux"
        case .playlist(let n): return n
        case .favorites: return "Favoris"
        case .fixed(let t, _): return t
        }
    }

    private var tracks: [Track] {
        switch source {
        case .album(let k): return lib.album(k)?.tracks ?? []
        case .genre(let n): return lib.genreTracks(n)
        case .artist(let n): return lib.artistTracks(n)
        case .songs: return lib.tracks
        case .playlist(let n): return playlists.tracks(n)
        case .favorites: return playlists.favoriteTracks()
        case .fixed(_, let t): return t
        }
    }

    private var playlistName: String? {
        if case .playlist(let n) = source { return n }
        return nil
    }

    private var isAlbum: Bool {
        if case .album = source { return true }
        return false
    }

    private var shown: [Track] {
        let all = tracks
        let q = query.trimmed
        if q.isEmpty { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q)
                || $0.album.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        let list = shown
        VStack(spacing: 0) {
            PageBar(title: title, search: $query)
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isAlbum, case .album(let k) = source, let a = lib.album(k) {
                        VStack(spacing: 6) {
                            ArtView(tracks: a.tracks).frame(width: 200, height: 200)
                            Text(a.name)
                                .font(.system(size: 21, weight: .bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(a.artist).font(.system(size: 16)).foregroundColor(Theme.accent).lineLimit(1)
                            Text("\(a.tracks.count) morceaux").font(.system(size: 13)).foregroundColor(Theme.gray)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                    }
                    if !list.isEmpty {
                        ShuffleRow { player.play(list, start: -1, shuffle: true) }
                    }
                    if list.isEmpty {
                        Text(query.isEmpty ? "Aucun morceau" : "Aucun résultat")
                            .foregroundColor(Theme.gray)
                            .padding(24)
                    }
                    ForEach(Array(list.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, subtitle: isAlbum ? nil : t.artist + " — " + t.album,
                                 actions: actions, playlist: playlistName,
                                 position: query.trimmed.isEmpty ? i : nil) {
                            player.play(list, start: i, shuffle: false)
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .trackActionHost(actions)
    }
}

// MARK: - Cartes d'albums

struct AlbumCard: View {
    let album: Album
    var size: CGFloat = 104
    @ObservedObject private var player = PlayerEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                NavigationLink {
                    SongListView(source: .album(album.key))
                } label: {
                    ArtView(tracks: album.tracks).frame(width: size, height: size)
                }
                .buttonStyle(.plain)
                Button {
                    player.play(album.tracks, start: 0, shuffle: false)
                } label: {
                    Icon("ic_play", size: 16, color: .white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.accent))
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                SongListView(source: .album(album.key))
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(album.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.black).lineLimit(1)
                    Text(album.artist).font(.system(size: 13)).foregroundColor(Theme.gray).lineLimit(1)
                }
                .frame(width: size, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(width: size, alignment: .leading)
    }
}

struct AlbumCarousel: View {
    let albums: [Album]
    var size: CGFloat = 104
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(albums) { a in AlbumCard(album: a, size: size) }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: size + 52)
    }
}

struct AlbumRowLink: View {
    let album: Album
    var body: some View {
        RowShell {
            NavigationLink {
                SongListView(source: .album(album.key))
            } label: {
                RowLabel(art: ArtView(tracks: album.tracks), title: album.name,
                         sub: album.artist + " • \(album.tracks.count) morceaux")
            }
            .buttonStyle(RowPressStyle())
        } trailing: {
            Icon("ic_chevron_right", size: 24, color: Theme.gray).frame(width: 40, height: 72)
        }
    }
}

// MARK: - Pour vous

struct ForYouView: View {
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = PlayerEngine.shared
    @EnvironmentObject private var app: AppState
    @State private var heavy: [Album] = []
    @State private var picks: [Album] = []

    private func reload(_ albums: [Album]) {
        var seen = Set<String>()
        var h: [Album] = []
        for t in player.heavyRotation(30) {
            if let a = lib.album(t.albumKey), seen.insert(a.key).inserted { h.append(a) }
        }
        var p = albums.filter { !seen.contains($0.key) }
        p.shuffle()
        heavy = h
        picks = Array(p.prefix(12))
    }

    var body: some View {
        TabScreen("Pour vous") {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if lib.isEmpty {
                        EmptyStateView(title: "Aucune musique",
                                       message: "Ajoutez des morceaux depuis l'onglet Import.")
                    } else {
                        if heavy.isEmpty {
                            Text("Écoutez de la musique et vos préférés apparaîtront ici.")
                                .font(.system(size: 15))
                                .foregroundColor(Theme.gray)
                                .padding(16)
                        } else {
                            SectionHeader("Les plus écoutés", big: true)
                            AlbumCarousel(albums: heavy, size: 140)
                        }
                        if !picks.isEmpty {
                            SectionHeader("Sélection pour vous", big: true)
                            AlbumCarousel(albums: picks, size: 140)
                        }
                        let recent = lib.recentAlbums(30)
                        if !recent.isEmpty {
                            SectionHeader("Nouveautés", big: true)
                            ForEach(recent) { a in AlbumRowLink(album: a) }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .onAppear { reload(lib.albums) }
            .onReceive(lib.$albums) { reload($0) }
            .onChange(of: app.tab) { t in
                if t == 0 { reload(lib.albums) }
            }
        }
    }
}

// MARK: - Ma musique

enum CategoryKind: Int {
    case genres = 0, artists, albums, songs
    var title: String {
        switch self {
        case .genres: return "Genres"
        case .artists: return "Artistes"
        case .albums: return "Albums"
        case .songs: return "Morceaux"
        }
    }
}

struct MyMusicView: View {
    @EnvironmentObject private var app: AppState
    @State private var segment = 0
    @State private var query = ""

    var body: some View {
        TabScreen("Ma musique", search: $query,
                  center: AnyView(KSegmented(labels: ["Bibliothèque", "Playlists"], selection: $segment)),
                  leading: {
            Button {
                app.showProfile = true
            } label: {
                Image("ic_profile")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
        }, content: {
            VStack(spacing: 0) {
                if segment == 0 { LibraryList(query: query) } else { PlaylistsList() }
            }
        })
    }
}

struct LibraryList: View {
    let query: String
    @ObservedObject private var lib = MusicLibrary.shared
    @ObservedObject private var player = PlayerEngine.shared
    @EnvironmentObject private var app: AppState
    @StateObject private var actions = TrackActions()
    @State private var kind: CategoryKind = .albums

    var body: some View {
        Group {
            if lib.isEmpty {
                ScrollView {
                    EmptyStateView(title: "Aucune musique",
                                   message: "Ajoutez des morceaux depuis l'onglet Import, ou copiez des fichiers dans le dossier KalisMusic/Music de l'application Fichiers.",
                                   buttonTitle: "Ajouter de la musique") { app.tab = 3 }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if query.trimmed.isEmpty { regularContent } else { searchContent }
                    }
                }
            }
        }
        .trackActionHost(actions)
    }

    @ViewBuilder
    private var regularContent: some View {
        ShuffleRow(label: "Shuffle") { player.play(lib.tracks, start: -1, shuffle: true) }
        let recent = lib.recentAlbums(12)
        if !recent.isEmpty {
            SectionHeader("AJOUTÉS RÉCEMMENT")
            AlbumCarousel(albums: recent)
        }
        categoryChooser
        switch kind {
        case .genres:
            ForEach(lib.genreNames, id: \.self) { n in
                NameRowLink(name: n, tracks: lib.genreTracks(n), source: .genre(n))
            }
        case .artists:
            ForEach(lib.artistNames, id: \.self) { n in
                NameRowLink(name: n, tracks: lib.artistTracks(n), source: .artist(n))
            }
        case .albums:
            ForEach(lib.albums) { a in AlbumRowLink(album: a) }
        case .songs:
            let all = lib.tracks
            ForEach(Array(all.enumerated()), id: \.offset) { i, t in
                TrackRow(track: t, subtitle: t.artist + " — " + t.album, actions: actions) {
                    player.play(all, start: i, shuffle: false)
                }
            }
        }
    }

    private var categoryChooser: some View {
        Menu {
            Button("Genres") { kind = .genres }
            Button("Artistes") { kind = .artists }
            Button("Albums") { kind = .albums }
            Button("Morceaux") { kind = .songs }
        } label: {
            HStack(spacing: 0) {
                Rectangle().fill(Theme.accent).frame(height: 1)
                HStack(spacing: 2) {
                    Text(kind.title).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.accent)
                    Icon("ic_chevron_down", size: 22, color: Theme.accent)
                }
                .padding(.horizontal, 10)
                Rectangle().fill(Theme.accent).frame(height: 1)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        let found = lib.search(query)
        if found.isEmpty {
            Text("Aucun résultat").foregroundColor(Theme.gray).padding(24)
        }
        ForEach(Array(found.enumerated()), id: \.offset) { i, t in
            TrackRow(track: t, subtitle: t.artist + " — " + t.album, actions: actions) {
                player.play(found, start: i, shuffle: false)
            }
        }
    }
}

struct NameRowLink: View {
    let name: String
    let tracks: [Track]
    let source: ListSource
    @ObservedObject private var lib = MusicLibrary.shared

    var body: some View {
        RowShell {
            NavigationLink {
                SongListView(source: source)
            } label: {
                RowLabel(art: ArtView(tracks: tracks), title: name,
                         sub: "\(lib.albumCount(tracks)) albums • \(tracks.count) morceaux")
            }
            .buttonStyle(RowPressStyle())
        } trailing: {
            Icon("ic_chevron_right", size: 24, color: Theme.gray).frame(width: 40, height: 72)
        }
    }
}

struct PlaylistsList: View {
    @ObservedObject private var playlists = PlaylistStore.shared
    @State private var showNew = false
    @State private var deleting: String?

    private func iconArt(_ name: String) -> some View {
        Theme.artBg.overlay(Icon(name, size: 26, color: Theme.accent))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                RowShell {
                    NavigationLink {
                        SongListView(source: .favorites)
                    } label: {
                        RowLabel(art: iconArt("ic_heart_filled"), title: "Favoris",
                                 sub: "\(playlists.favoriteTracks().count) morceaux")
                    }
                    .buttonStyle(RowPressStyle())
                } trailing: {
                    Icon("ic_chevron_right", size: 24, color: Theme.gray).frame(width: 40, height: 72)
                }
                ForEach(playlists.names, id: \.self) { n in
                    RowShell {
                        NavigationLink {
                            SongListView(source: .playlist(n))
                        } label: {
                            RowLabel(art: iconArt("ic_list"), title: n, sub: "\(playlists.count(n)) morceaux")
                        }
                        .buttonStyle(RowPressStyle())
                    } trailing: {
                        Menu {
                            Button("Supprimer la playlist", role: .destructive) { deleting = n }
                        } label: {
                            Icon("ic_more", size: 24, color: Theme.accent).frame(width: 52, height: 72)
                        }
                    }
                }
                Button {
                    showNew = true
                } label: {
                    HStack(spacing: 12) {
                        Icon("ic_add", size: 24, color: Theme.accent)
                        Text("Nouvelle playlist…").font(.system(size: 18)).foregroundColor(Theme.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
            }
        }
        .sheet(isPresented: $showNew) {
            NamePromptView(title: "Nouvelle playlist", placeholder: "Nom de la playlist", confirm: "Créer") { n in
                playlists.create(n)
            }
        }
        .alert("Supprimer cette playlist ?", isPresented: Binding(get: { deleting != nil },
                                                                   set: { if !$0 { deleting = nil } })) {
            Button("Supprimer", role: .destructive) {
                if let d = deleting { playlists.delete(d) }
                deleting = nil
            }
            Button("Annuler", role: .cancel) { deleting = nil }
        }
    }
}
