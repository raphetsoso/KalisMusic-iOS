import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject private var store = StoreData.shared
    @ObservedObject private var toast = ToastCenter.shared
    @State private var visited: Set<Int> = [4]

    @ViewBuilder
    private func screen(_ tag: Int) -> some View {
        switch tag {
        case 0: ForYouView()
        case 1: StoreView()
        case 2: RadioView()
        case 3: ImportView()
        default: MyMusicView()
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ZStack {
                    ForEach(0..<5, id: \.self) { tag in
                        if visited.contains(tag) && !(tag == 1 && store.hidden) {
                            screen(tag)
                                .opacity(app.tab == tag ? 1 : 0)
                                .allowsHitTesting(app.tab == tag)
                        }
                    }
                }
                MiniPlayerView()
                KTabBar(tab: $app.tab, showStore: !store.hidden)
            }
            .background(Color.white)

            if let m = toast.message {
                Text(m)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: toast.message)
        .onChange(of: app.tab) { t in visited.insert(t) }
        .onChange(of: store.hidden) { hidden in
            if hidden && app.tab == 1 { app.tab = 4 }
        }
        .fullScreenCover(isPresented: $app.showNowPlaying) { NowPlayingView() }
        .sheet(isPresented: $app.showProfile) { ProfileView() }
    }
}

@main
struct KalisMusicApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var phase

    init() {
        Paths.prepare()
        PlayerEngine.shared.configure()
        MusicLibrary.shared.refresh()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    // « Ouvrir avec KalisMusic » depuis Fichiers, Safari…
                    Task {
                        let res = await Importer.importAsync([url], move: false) { _, _, _ in }
                        await MainActor.run {
                            ToastCenter.shared.show("\(res.added) ajoutés, \(res.skipped) ignorés")
                            MusicLibrary.shared.refresh()
                        }
                    }
                }
        }
        .onChange(of: phase) { p in
            if p == .active {
                MusicLibrary.shared.refresh()
            } else {
                StatsStore.shared.flush()
            }
        }
    }
}
