import AVFoundation
import MediaPlayer

enum LoopMode {
    case off, all, one
    var next: LoopMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

final class PlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var currentID: UUID?
    @Published var isPlaying = false
    @Published var shuffle = false
    @Published var loop: LoopMode = .off
    @Published var time: Double = 0
    @Published var duration: Double = 0

    var library: Library?
    private var player: AVAudioPlayer?
    private var queue: [Song] = []
    private var order: [Song] = []
    private var index = 0
    private var timer: Timer?

    var current: Song? { library?.songs.first { $0.id == currentID } }

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        configureRemote()
        observeInterruptions()
    }

    // MARK: Queue

    func play(songs: [Song], start: Song? = nil, shuffle forced: Bool? = nil) {
        guard !songs.isEmpty else { return }
        if let f = forced { shuffle = f }
        queue = songs
        let first = start ?? (shuffle ? songs.randomElement()! : songs[0])
        buildOrder(start: first)
        load()
    }

    private func buildOrder(start: Song) {
        if shuffle {
            order = [start] + queue.filter { $0.id != start.id }.shuffled()
        } else {
            order = queue
        }
        index = order.firstIndex { $0.id == start.id } ?? 0
    }

    func toggleShuffle() {
        shuffle.toggle()
        if let c = current, !queue.isEmpty { buildOrder(start: c) }
    }

    func cycleLoop() { loop = loop.next }

    private func load() {
        guard order.indices.contains(index), let lib = library else { return }
        let song = order[index]
        do {
            let p = try AVAudioPlayer(contentsOf: lib.fileURL(song))
            p.delegate = self
            p.prepareToPlay()
            p.play()
            player = p
            currentID = song.id
            duration = p.duration
            time = 0
            isPlaying = true
            startTimer()
            updateNowPlaying()
        } catch {
            stopAll()
        }
    }

    func advance(auto: Bool) {
        guard !order.isEmpty else { return }
        if auto && loop == .one {
            player?.currentTime = 0
            player?.play()
            return
        }
        if index + 1 >= order.count {
            if loop == .all || !auto {
                if shuffle && loop == .all { order.shuffle() }
                index = 0
                load()
            } else {
                isPlaying = false
                time = 0
                timer?.invalidate()
                updateNowPlaying()
            }
        } else {
            index += 1
            load()
        }
    }

    func previous() {
        guard !order.isEmpty else { return }
        if (player?.currentTime ?? 0) > 3 {
            seek(0)
        } else {
            index = index > 0 ? index - 1 : order.count - 1
            load()
        }
    }

    func remove(_ id: UUID) {
        queue.removeAll { $0.id == id }
        guard let i = order.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = currentID == id
        order.remove(at: i)
        if i < index { index -= 1 }
        if wasCurrent {
            if order.isEmpty {
                stopAll()
            } else {
                if index >= order.count { index = 0 }
                load()
            }
        }
    }

    private func stopAll() {
        player?.stop()
        player = nil
        timer?.invalidate()
        currentID = nil
        isPlaying = false
        queue = []
        order = []
        time = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: Transport

    func resume() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func togglePlay() { isPlaying ? pause() : resume() }

    func seek(_ t: Double) {
        player?.currentTime = t
        time = t
        updateNowPlaying()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self, let p = self.player else { return }
            self.time = p.currentTime
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.advance(auto: true) }
    }

    // MARK: Lock screen & interruptions

    private func updateNowPlaying() {
        guard let song = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }

    private func configureRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.advance(auto: false); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }
            return .success
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                               object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self?.pause()
            } else if let o = n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                      AVAudioSession.InterruptionOptions(rawValue: o).contains(.shouldResume) {
                self?.resume()
            }
        }
    }
}
