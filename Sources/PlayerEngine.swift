import Foundation
import AVFoundation
import MediaPlayer
import UIKit

/// Position de lecture, publiée à part : sinon toutes les listes se redessineraient deux fois par seconde.
final class PlaybackClock: ObservableObject {
    static let shared = PlaybackClock()
    @Published var position: Double = 0
}

final class PlayerEngine: ObservableObject {
    static let shared = PlayerEngine()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var duration: Double = 0
    @Published var errorMessage: String?

    let clock = PlaybackClock.shared
    var position: Double { clock.position }
    var current: Track? { (index >= 0 && index < queue.count) ? queue[index] : nil }

    private let player = AVPlayer()
    /// Titre en cours annoncé par la webradio (métadonnées ICY lues par le lecteur) ; sert aussi à l'enregistreur.
    private(set) var liveTitle: String?
    private let metaDelegate = LiveMetaDelegate()
    private var timeObserver: Any?
    private var rateObs: NSKeyValueObservation?
    private var itemObs: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var wantPlay = false
    private var itemLoading = false
    private var resumeAfterInterruption = false
    private var errorStreak = 0
    private var loadToken = 0
    private var lastTick: Date?
    private var artwork: MPMediaItemArtwork?
    private var counted = false
    private var configured = false
    private var plays: [String: Int]

    private init() {
        plays = (UserDefaults.standard.dictionary(forKey: "kalis_plays") as? [String: Int]) ?? [:]
        player.automaticallyWaitsToMinimizeStalling = true
    }

    // MARK: Configuration (une seule fois, au lancement)

    func configure() {
        if configured { return }
        configured = true

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] t in
            self?.tick(t)
        }
        rateObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.syncState() }
        }

        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            self?.handleInterruption(n)
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            self?.handleRouteChange(n)
        }
        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        let all: [MPRemoteCommand] = [c.playCommand, c.pauseCommand, c.togglePlayPauseCommand,
                                      c.nextTrackCommand, c.previousTrackCommand, c.changePlaybackPositionCommand]
        for cmd in all { cmd.isEnabled = true }
        c.playCommand.addTarget { [weak self] _ in
            self?.playIfPaused()
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    // MARK: Commandes

    /// Lance la lecture d'une liste. start < 0 : premier morceau (ou au hasard si shuffle).
    func play(_ list: [Track], start: Int, shuffle: Bool) {
        if list.isEmpty { return }
        var q = list
        var s = max(0, start)
        if shuffle {
            let first: Track? = (start >= 0 && start < q.count) ? q[start] : nil
            q.shuffle()
            if let f = first, let i = q.firstIndex(of: f) {
                q.remove(at: i)
                q.insert(f, at: 0)
            }
            s = 0
        }
        queue = q
        index = s
        wantPlay = true
        errorStreak = 0
        startCurrent()
    }

    func togglePlayPause() {
        if player.currentItem == nil {
            if !queue.isEmpty {
                if index < 0 { index = 0 }
                wantPlay = true
                startCurrent()
            }
            return
        }
        if isPlaying { pause() } else { playIfPaused() }
    }

    func playIfPaused() {
        guard current != nil else { return }
        if player.currentItem == nil || errorMessage != nil {
            wantPlay = true
            startCurrent()
            return
        }
        // un direct qui a été mis en pause longtemps reprend « en direct »
        if current?.stream == true {
            wantPlay = true
            startCurrent()
            return
        }
        wantPlay = true
        activateSession()
        player.play()
        syncState()
    }

    func pause() {
        wantPlay = false
        resumeAfterInterruption = false
        player.pause()
        syncState()
    }

    func next() {
        if queue.isEmpty { return }
        index = index + 1 < queue.count ? index + 1 : 0
        wantPlay = true
        errorStreak = 0
        startCurrent()
    }

    func previous() {
        if queue.isEmpty { return }
        if position > 3, current?.stream != true {
            seek(to: 0)
            return
        }
        index = index > 0 ? index - 1 : 0
        wantPlay = true
        errorStreak = 0
        startCurrent()
    }

    func jumpTo(_ i: Int) {
        if i < 0 || i >= queue.count { return }
        index = i
        wantPlay = true
        errorStreak = 0
        startCurrent()
    }

    func seek(to seconds: Double) {
        guard player.currentItem != nil, current?.stream != true else { return }
        let t = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        clock.position = max(0, seconds)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async { self?.updateNowPlaying() }
        }
    }

    func playNext(_ t: Track) {
        if queue.isEmpty {
            play([t], start: 0, shuffle: false)
            return
        }
        queue.insert(t, at: min(index + 1, queue.count))
    }

    func addToQueue(_ t: Track) {
        if queue.isEmpty {
            play([t], start: 0, shuffle: false)
            return
        }
        queue.append(t)
    }

    func stop() {
        wantPlay = false
        loadToken += 1
        teardownItem()
        player.replaceCurrentItem(with: nil)
        queue = []
        index = -1
        clock.position = 0
        duration = 0
        StreamRecorder.shared.playbackChanged(current: nil)
        syncState()
        updateNowPlaying()
    }

    // MARK: Chargement d'un morceau

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func teardownItem() {
        itemObs = nil
        if let e = endObserver {
            NotificationCenter.default.removeObserver(e)
            endObserver = nil
        }
    }

    private func startCurrent() {
        guard let t = current else { return }
        loadToken += 1
        let token = loadToken
        teardownItem()
        clock.position = 0
        duration = t.duration
        itemLoading = true
        counted = false
        errorMessage = nil
        artwork = nil
        lastTick = nil
        StreamRecorder.shared.playbackChanged(current: t)
        activateSession()
        syncState()
        updateNowPlaying()
        loadArtwork(for: t, token: token)

        if t.stream {
            Task {
                let r = await StreamResolver.resolve(t.source, name: t.title)
                await MainActor.run {
                    guard token == self.loadToken else { return }
                    guard let u = r.url, let url = URL(string: Ncs.encodeUrl(u)) else {
                        self.fail(r.error ?? L("flux introuvable"))
                        return
                    }
                    self.begin(url: url)
                }
            }
        } else {
            let url = Paths.url(forSource: t.source)
            if !FileManager.default.fileExists(atPath: url.path) {
                fail(L("Fichier introuvable"))
                return
            }
            begin(url: url)
        }
    }

    private func begin(url: URL) {
        let item = AVPlayerItem(url: url)
        liveTitle = nil
        if current?.stream == true {
            metaDelegate.onTitle = { [weak self] t in self?.liveTitle = t }
            let out = AVPlayerItemMetadataOutput(identifiers: nil)
            out.setDelegate(metaDelegate, queue: DispatchQueue.main)
            item.add(out)
        }
        itemObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            DispatchQueue.main.async { self?.itemStatusChanged(it) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                             queue: .main) { [weak self] _ in
            self?.trackEnded()
        }
        player.replaceCurrentItem(with: item)
        if wantPlay { player.play() }
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            itemLoading = false
            errorStreak = 0
            let d = item.duration.seconds
            if let t = current, !t.stream, d.isFinite, d > 0 { duration = d }
            if wantPlay, !counted, let t = current, !t.stream {
                counted = true
                bumpPlayCount(t)
            }
            syncState()
            updateNowPlaying()
        case .failed:
            fail(item.error?.localizedDescription ?? L("lecture impossible"))
        default:
            break
        }
    }

    private func trackEnded() {
        guard let t = current else { return }
        if t.stream {                      // un flux qui se coupe n'est pas une fin de morceau
            fail(L("flux interrompu"))
            return
        }
        if index + 1 < queue.count {
            index += 1
            wantPlay = true
            startCurrent()
        } else {
            // fin de la file : on se replace au début, en pause
            index = 0
            wantPlay = false
            startCurrent()
        }
    }

    private func fail(_ msg: String) {
        itemLoading = false
        errorStreak += 1
        let limit = min(max(queue.count, 1), 5)
        if let t = current, !t.stream, errorStreak < limit, index + 1 < queue.count {
            index += 1
            startCurrent()
            return
        }
        if current?.stream == true {
            errorMessage = L("Station indisponible. Vérifiez votre connexion ou l'adresse du flux.")
        } else {
            errorMessage = L("Lecture impossible : ") + msg
        }
        wantPlay = false
        player.pause()
        syncState()
    }

    // MARK: État

    private func syncState() {
        let s = player.timeControlStatus
        isPlaying = (s != .paused)
        isLoading = itemLoading || s == .waitingToPlayAtSpecifiedRate
        if player.currentItem == nil { isPlaying = false }
        updateNowPlaying()
    }

    private func tick(_ t: CMTime) {
        let s = t.seconds
        if s.isFinite, s >= 0 { clock.position = s }
        let now = Date()
        if player.timeControlStatus == .playing, let last = lastTick, let cur = current {
            let d = now.timeIntervalSince(last)
            if d > 0 && d < 15 { StatsStore.shared.addListen(cur, ms: Int64(d * 1000)) }
        }
        lastTick = player.timeControlStatus == .playing ? now : nil
        if let it = player.currentItem, let cur = current, !cur.stream {
            let d = it.duration.seconds
            if d.isFinite, d > 0, abs(d - duration) > 0.5 { duration = d }
        }
    }

    // MARK: Interruptions

    private func handleInterruption(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // wantPlay et non isPlaying : le lecteur est déjà en pause quand la notification arrive
            if wantPlay { resumeAfterInterruption = true }
        case .ended:
            let optRaw = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let opts = AVAudioSession.InterruptionOptions(rawValue: optRaw)
            if resumeAfterInterruption && opts.contains(.shouldResume) && wantPlay {
                activateSession()
                player.play()
            }
            resumeAfterInterruption = false
        @unknown default:
            break
        }
        syncState()
    }

    private func handleRouteChange(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable { pause() }   // casque débranché
    }

    // MARK: Écran verrouillé / Centre de contrôle

    private func loadArtwork(for t: Track, token: Int) {
        Task {
            guard let img = await ArtLoader.image(for: t) else { return }
            await MainActor.run {
                guard token == self.loadToken else { return }
                self.artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                self.updateNowPlaying()
            }
        }
    }

    private func updateNowPlaying() {
        guard let t = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyIsLiveStream: t.stream
        ]
        if duration > 0 && !t.stream { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let a = artwork { info[MPMediaItemPropertyArtwork] = a }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Compteur d'écoutes (« Les plus écoutés »)

    private func bumpPlayCount(_ t: Track) {
        plays[t.source, default: 0] += 1
        UserDefaults.standard.set(plays, forKey: "kalis_plays")
        StatsStore.shared.addPlay(t)
    }

    func heavyRotation(_ limit: Int) -> [Track] {
        let keys = plays.sorted { $0.value > $1.value }.map { $0.key }
        var out: [Track] = []
        for k in keys {
            if let t = MusicLibrary.shared.byPath(k) { out.append(t) }
            if out.count >= limit { break }
        }
        return out
    }

    /// Compteurs pour la sauvegarde : chemin -> nombre.
    func playsExport() -> [String: Int] { plays }

    /// Restaure les compteurs ; les chemins sont retrouvés par nom de fichier.
    func playsRestore(_ o: [String: Int], byName: [String: String]) {
        for (k, v) in o {
            let path = byName[k.fileNameLower] ?? k
            plays[path] = v
        }
        UserDefaults.standard.set(plays, forKey: "kalis_plays")
    }
}


/// Reçoit les titres des webradios (métadonnées ICY / timed metadata).
final class LiveMetaDelegate: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    var onTitle: ((String) -> Void)?

    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        for g in groups {
            for item in g.items {
                let key = (item.key as? String) ?? ""
                let isTitle = key == "StreamTitle" || item.commonKey == .commonKeyTitle
                if isTitle, let s = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                    onTitle?(s)
                    return
                }
            }
        }
    }
}
