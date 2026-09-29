import AVFoundation
import XCTest
@testable import KittyClan

final class AudioTests: XCTestCase {
    private let spring = AudioScene.clan(biome: .forest, camp: 4, season: .newleaf)

    func testPlaylistsFollowClangen() {
        let library = AudioLibrary.bundled
        XCTAssertEqual(library.musicPlaylist(for: .menu), ["music/Generations.mp3"])
        let general = library.musicPlaylist(for: .clan(biome: .forest, camp: 1, season: .greenleaf))
        XCTAssertEqual(general.count, 6)
        XCTAssertEqual(library.musicPlaylist(for: .clan(biome: .beach, camp: 1, season: .leafBare)), general + ["music/Leafbare.mp3"])
        XCTAssertEqual(library.musicPlaylist(for: spring), general + ["music/Newleaf.mp3"])
        XCTAssertEqual(library.ambienceBase(for: .menu), ["ambiance/menu_ambiance.mp3"])
        XCTAssertEqual(library.ambienceBase(for: .clan(biome: .mountainous, camp: 1, season: .newleaf)), ["ambiance/biome_mountainous/mountain_base.mp3"])
        XCTAssertEqual(library.campOverlays(biome: .forest, camp: 4).count, 3, "Lakeside has its own sounds")
        XCTAssertEqual(library.campOverlays(biome: .mountainous, camp: 3).count, 3, "Crystal River has its own sounds")
        XCTAssertEqual(library.campOverlays(biome: .forest, camp: 1), [])
        XCTAssertEqual(library.seasonOverlays(.leafFall).first, "ambiance/seasonal/leaffall_crows.mp3")
        XCTAssertEqual(library.sounds(.diceRoll).count, 7)
    }

    func testNextTrackAvoidsRepeats() {
        var rng = SeededRNG(seed: 4)
        for _ in 0..<50 {
            XCTAssertEqual(AudioLibrary.nextTrack(from: ["a", "b"], after: "a", using: &rng), "b")
        }
        XCTAssertEqual(AudioLibrary.nextTrack(from: ["a"], after: "a", using: &rng), "a")
        XCTAssertNil(AudioLibrary.nextTrack(from: [], after: nil, using: &rng))
    }

    @MainActor
    func testSilentWithoutBundledAudio() {
        let director = AudioDirector(library: AudioLibrary(directory: nil), defaults: freshDefaults())
        director.setScene(.menu)
        director.play(.timeskip)
        XCTAssertFalse(director.library.hasAudioFiles)
        XCTAssertFalse(director.isMusicPlaying)
        XCTAssertEqual(director.playingSoundCount, 0)
    }

    @MainActor
    func testPlaysMusicAmbienceAndSoundsForTheScene() async throws {
        let library = try makeLibrary()
        XCTAssertTrue(library.hasAudioFiles)
        var timing = AudioDirector.Timing()
        timing.musicSilence = 0.2...0.2
        timing.overlaySilence = 0.1...0.1
        timing.menuSwitchFade = 0.1
        timing.musicFadeOut = 0.1
        timing.firstTrackDelay = 0.1
        let defaults = freshDefaults()
        let director = AudioDirector(library: library, defaults: defaults, timing: timing)

        director.setScene(.menu)
        try await waitUntil { director.isMusicPlaying && director.isAmbiencePlaying }
        XCTAssertEqual(director.currentMusic, "music/Generations.mp3")
        XCTAssertEqual(director.currentAmbience, "ambiance/menu_ambiance.mp3")

        director.setScene(spring)
        XCTAssertNil(director.currentMusic, "menu music fades out when the Clan opens")
        try await waitUntil { director.currentAmbience == "ambiance/biome_forest/forest_base.mp3" && director.isAmbiencePlaying }
        try await waitUntil { director.currentMusic != nil }
        XCTAssertTrue(["music/Dawn_Patrol.mp3", "music/Newleaf.mp3"].contains(director.currentMusic ?? ""))
        XCTAssertTrue(director.isMusicPlaying)

        director.play(.diceRoll)
        XCTAssertEqual(director.playingSoundCount, 1)
        director.isSoundEffectsOn = false
        director.play(.diceRoll)
        XCTAssertLessThanOrEqual(director.playingSoundCount, 1)

        director.isMusicOn = false
        XCTAssertNil(director.currentMusic)
        XCTAssertNil(director.currentAmbience)
        XCTAssertFalse(defaults.bool(forKey: AudioDirector.Key.music))

        director.isMusicOn = true
        try await waitUntil { director.isMusicPlaying && director.currentAmbience == "ambiance/biome_forest/forest_base.mp3" }
        director.musicVolume = 0.25
        XCTAssertEqual(defaults.double(forKey: AudioDirector.Key.musicVolume), 0.25)
    }

    private func freshDefaults() -> UserDefaults {
        let name = "AudioTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @MainActor
    private func waitUntil(timeout: Double = 5, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// A small Audio folder with Clangen's layout: a few tracks as one-second tones.
    private func makeLibrary() throws -> AudioLibrary {
        let root = FileManager.default.temporaryDirectory.appending(path: "Audio-\(UUID().uuidString)")
        let files: [String: Any] = [
            "music.json": ["menu_playlist": ["Generations.mp3"], "general_playlist": ["Dawn_Patrol.mp3"], "newleaf_playlist": ["Newleaf.mp3"]],
            "ambiance.json": [
                "menu_playlist": ["menu_ambiance.mp3"],
                "seasonal": ["newleaf": ["seasonal/newleaf_rain.mp3"]],
                "forest": ["base": ["biome_forest/forest_base.mp3"], "lakeside": ["biome_forest/lakeside_waves.mp3"]],
            ],
            "sounds.json": ["dice_roll": ["Dice_roll_1.mp3"]],
        ]
        for (name, value) in files {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value).write(to: root.appending(path: name))
        }
        for path in [
            "music/Generations", "music/Dawn_Patrol", "music/Newleaf", "ambiance/menu_ambiance",
            "ambiance/seasonal/newleaf_rain", "ambiance/biome_forest/forest_base", "ambiance/biome_forest/lakeside_waves",
            "sounds/Dice_roll_1",
        ] {
            try writeTone(to: root.appending(path: path + ".caf"), seconds: 2)
        }
        return AudioLibrary(directory: root)
    }

    private func writeTone(to url: URL, seconds: Double) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let frames = AVAudioFrameCount(22_050 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { samples[i] = 0.1 * sin(Float(i) * 2 * .pi * 440 / 22_050) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
