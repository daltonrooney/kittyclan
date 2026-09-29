import AVFoundation
import Foundation
import Observation
import os

/// Plays Clangen's music, ambience and UI sounds for the current scene, with the viewer's audio settings.
///
/// Music follows Clangen's `Music`: one track at a time from the scene's playlist, then a random silence
/// before the next. Ambience follows its `Ambiance`: a base track that plays continuously, with camp and
/// season sounds laid over it now and then. Tracks that aren't bundled are skipped.
@MainActor
@Observable
final class AudioDirector {
    /// How long Clangen waits and fades, in seconds. Tests shorten these.
    struct Timing: Sendable {
        var musicSilence: ClosedRange<Double> = 30...250
        var overlaySilence: ClosedRange<Double> = 20...50
        var musicFadeIn = 3.0
        var musicFadeOut = 2.0
        var menuSwitchFade = 3.0
        var ambienceFadeIn = 3.0
        var ambienceFadeOut = 2.0
        /// Before the first track when the app opens straight into a Clan, which Clangen never does.
        var firstTrackDelay = 3.0

        static let clangen = Timing()
    }

    enum Key {
        static let music = "audio.music"
        static let soundEffects = "audio.soundEffects"
        static let musicVolume = "audio.musicVolume"
        static let ambienceVolume = "audio.ambienceVolume"
        static let soundVolume = "audio.soundVolume"
    }

    /// Music and ambience.
    var isMusicOn: Bool {
        didSet {
            defaults.set(isMusicOn, forKey: Key.music)
            if isMusicOn { refresh() } else { stopBackground() }
        }
    }
    var isSoundEffectsOn: Bool {
        didSet { defaults.set(isSoundEffectsOn, forKey: Key.soundEffects) }
    }
    var musicVolume: Double {
        didSet {
            defaults.set(musicVolume, forKey: Key.musicVolume)
            musicPlayer?.volume = Float(musicVolume)
        }
    }
    var ambienceVolume: Double {
        didSet {
            defaults.set(ambienceVolume, forKey: Key.ambienceVolume)
            ambiencePlayer?.volume = Float(ambienceVolume)
            for player in overlayPlayers.values { player.volume = Float(overlayVolume) }
        }
    }
    var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: Key.soundVolume) }
    }

    /// The music track playing, e.g. `music/Dawn_Patrol.mp3`.
    private(set) var currentMusic: String?
    private(set) var currentAmbience: String?

    let library: AudioLibrary
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let timing: Timing
    @ObservationIgnored private var scene: AudioScene?
    @ObservationIgnored private var lastMusic: String?
    @ObservationIgnored private var musicPlayer: AVAudioPlayer?
    @ObservationIgnored private var ambiencePlayer: AVAudioPlayer?
    @ObservationIgnored private var overlayPlayers: [String: AVAudioPlayer] = [:]
    @ObservationIgnored private var soundPlayers: [AVAudioPlayer] = []
    @ObservationIgnored private var musicTask: Task<Void, Never>?
    @ObservationIgnored private var ambienceTask: Task<Void, Never>?
    @ObservationIgnored private var overlayTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var rng = SystemRandomNumberGenerator()

    private static let log = Logger(subsystem: "com.madebyraygun.kittyclan", category: "audio")

    init(library: AudioLibrary = .bundled, defaults: UserDefaults = .standard, timing: Timing = .clangen) {
        self.library = library
        self.defaults = defaults
        self.timing = timing
        defaults.register(defaults: [
            Key.music: true, Key.soundEffects: true,
            Key.musicVolume: 0.5, Key.ambienceVolume: 0.5, Key.soundVolume: 0.5,
        ])
        isMusicOn = defaults.bool(forKey: Key.music)
        isSoundEffectsOn = defaults.bool(forKey: Key.soundEffects)
        musicVolume = defaults.double(forKey: Key.musicVolume)
        ambienceVolume = defaults.double(forKey: Key.ambienceVolume)
        soundVolume = defaults.double(forKey: Key.soundVolume)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient)
        } catch {
            Self.log.error("Couldn't set the ambient audio session: \(error.localizedDescription)")
        }
        if !library.hasAudioFiles {
            Self.log.info("No audio files are bundled; music, ambience and sound effects are silent")
        }
    }

    var isMusicPlaying: Bool { musicPlayer?.isPlaying ?? false }
    var isAmbiencePlaying: Bool { ambiencePlayer?.isPlaying ?? false }
    var playingSoundCount: Int { soundPlayers.count(where: \.isPlaying) }

    /// Clangen halves the ambience volume for the short overlay sounds.
    private var overlayVolume: Double { (ambienceVolume * 100 / 2).rounded(.down) / 100 }

    /// Moves to a new scene, changing music and ambience when they no longer fit (Clangen's `check`).
    func setScene(_ scene: AudioScene?) {
        let previous = self.scene
        self.scene = scene
        guard isMusicOn else { return }
        guard let scene else { return stopBackground() }
        checkMusic(for: scene, isFirst: previous == nil)
        if ambienceNeedsChange(from: previous, to: scene) { startAmbience(for: scene) }
    }

    func play(_ effect: SoundEffect) {
        guard isSoundEffectsOn else { return }
        soundPlayers.removeAll { !$0.isPlaying }
        guard let path = library.available(library.sounds(effect)).randomElement(using: &rng),
              let player = makePlayer(path, volume: soundVolume)
        else { return }
        player.play()
        soundPlayers.append(player)
    }

    // MARK: - Music

    private func checkMusic(for scene: AudioScene, isFirst: Bool) {
        let playlist = library.musicPlaylist(for: scene)
        if let current = currentMusic, playlist.contains(current) { return }
        switch scene {
        case .menu:
            if currentMusic != nil {
                fadeOutMusic(over: timing.menuSwitchFade)
                scheduleMusic(after: timing.menuSwitchFade)
            } else {
                scheduleMusic(after: 0)
            }
        case .clan:
            if currentMusic != nil {
                fadeOutMusic(over: timing.musicFadeOut)
                scheduleMusic(after: max(timing.musicFadeOut, silence()))
            } else if isFirst || musicTask == nil {
                scheduleMusic(after: timing.firstTrackDelay)
            }
        }
    }

    private func silence() -> Double {
        Double.random(in: timing.musicSilence, using: &rng)
    }

    private func scheduleMusic(after delay: Double) {
        musicTask?.cancel()
        musicTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.playMusic()
        }
    }

    private func playMusic() {
        guard isMusicOn, let scene else { return }
        let playlist = library.available(library.musicPlaylist(for: scene))
        guard let track = AudioLibrary.nextTrack(from: playlist, after: lastMusic, using: &rng),
              let player = makePlayer(track, volume: 0)
        else {
            Self.log.debug("No music to play for \(String(describing: scene))")
            musicTask = nil
            return
        }
        musicPlayer?.stop()
        musicPlayer = player
        player.play()
        player.setVolume(Float(musicVolume), fadeDuration: timing.musicFadeIn)
        currentMusic = track
        lastMusic = track
        Self.log.info("Playing music \(track)")
        let duration = player.duration
        musicTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.currentMusic = nil
            self.musicPlayer = nil
            self.scheduleMusic(after: self.silence())
        }
    }

    private func fadeOutMusic(over seconds: Double) {
        musicTask?.cancel()
        musicTask = nil
        if let player = musicPlayer {
            fadeOutAndStop(player, over: seconds)
        }
        musicPlayer = nil
        currentMusic = nil
    }

    // MARK: - Ambience

    private func ambienceNeedsChange(from previous: AudioScene?, to scene: AudioScene) -> Bool {
        switch (previous, scene) {
        case let (.clan(oldBiome, oldCamp, oldSeason)?, .clan(biome, camp, season)):
            if oldBiome != biome || oldCamp != camp { return true }
            return oldSeason != season ? false : ambienceTask == nil
        case (.menu?, .menu):
            return ambienceTask == nil
        default:
            return true
        }
    }

    private func startAmbience(for scene: AudioScene) {
        ambienceTask?.cancel()
        if let player = ambiencePlayer { fadeOutAndStop(player, over: timing.ambienceFadeOut) }
        ambiencePlayer = nil
        currentAmbience = nil
        stopOverlays()

        let playlist = library.available(library.ambienceBase(for: scene))
        ambienceTask = Task { [weak self] in
            var last: String?
            while !Task.isCancelled {
                guard let self, let track = self.nextAmbience(from: playlist, after: last) else { return }
                last = track
                guard let duration = self.playAmbience(track) else { return }
                try? await Task.sleep(for: .seconds(duration))
            }
        }
        if case let .clan(biome, camp, _) = scene {
            startOverlayLoop { $0.library.campOverlays(biome: biome, camp: camp) }
            startOverlayLoop { director in
                guard case let .clan(_, _, season) = director.scene else { return [] }
                return director.library.seasonOverlays(season)
            }
        }
    }

    private func nextAmbience(from playlist: [String], after last: String?) -> String? {
        AudioLibrary.nextTrack(from: playlist, after: last, using: &rng)
    }

    /// Starts a base track and returns how long it lasts.
    private func playAmbience(_ track: String) -> Double? {
        guard let player = makePlayer(track, volume: 0) else { return nil }
        ambiencePlayer = player
        player.play()
        player.setVolume(Float(ambienceVolume), fadeDuration: timing.ambienceFadeIn)
        currentAmbience = track
        Self.log.info("Playing ambience \(track)")
        return player.duration
    }

    /// Clangen's overlay timers: a random silence, then a random sound from the list, over and over.
    private func startOverlayLoop(_ tracks: @escaping @MainActor (AudioDirector) -> [String]) {
        let key = UUID().uuidString
        overlayTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(Double.random(in: self.timing.overlaySilence, using: &self.rng)))
                guard !Task.isCancelled else { return }
                let playlist = self.library.available(tracks(self))
                guard let track = playlist.randomElement(using: &self.rng),
                      let player = self.makePlayer(track, volume: self.overlayVolume)
                else { continue }
                self.overlayPlayers[key] = player
                player.play()
                try? await Task.sleep(for: .seconds(player.duration))
                self.overlayPlayers[key] = nil
            }
        })
    }

    private func stopOverlays() {
        for task in overlayTasks { task.cancel() }
        overlayTasks = []
        for player in overlayPlayers.values { fadeOutAndStop(player, over: 0.3) }
        overlayPlayers = [:]
    }

    // MARK: - Playback

    private func refresh() {
        let scene = self.scene
        self.scene = nil
        setScene(scene)
    }

    private func stopBackground() {
        fadeOutMusic(over: 0.5)
        ambienceTask?.cancel()
        ambienceTask = nil
        if let player = ambiencePlayer { fadeOutAndStop(player, over: 0.5) }
        ambiencePlayer = nil
        currentAmbience = nil
        stopOverlays()
    }

    private func makePlayer(_ path: String, volume: Double) -> AVAudioPlayer? {
        guard let url = library.url(path) else { return nil }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(volume)
            player.prepareToPlay()
            return player
        } catch {
            Self.log.error("Couldn't play \(path): \(error.localizedDescription)")
            return nil
        }
    }

    private func fadeOutAndStop(_ player: AVAudioPlayer, over seconds: Double) {
        player.setVolume(0, fadeDuration: seconds)
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            player.stop()
        }
    }
}
