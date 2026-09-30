import Foundation

/// Where the player is, which decides Clangen's music and ambience.
enum AudioScene: Hashable, Sendable {
    /// Choosing or founding a Clan (Clangen's menu screens).
    case menu
    case clan(biome: Biome, camp: Int, season: Season)
}

/// Clangen's UI sounds (`sounds.json` keys).
enum SoundEffect: String, CaseIterable, Sendable {
    case buttonPress = "button_press"
    case buttonHover = "button_hover"
    case pageFlip = "page_flip"
    case diceRoll = "dice_roll"
    case save
    case timeskip
    case antagonize
    case favoriteCat = "fav_cat"
}

/// Clangen's playlists (`music.json`, `ambiance.json`, `sounds.json`) and the audio files that are present.
/// Paths are relative to the Audio folder, e.g. `music/Generations.mp3`. A track counts as present when that
/// file exists, or the same name with an `.m4a` or `.caf` extension does, so tracks can be re-encoded.
struct AudioLibrary: Sendable {
    let directory: URL?
    private let music: [String: [String]]
    private let ambienceBase: [String: [String]]
    private let overlays: [String: [String]]
    private let menuAmbience: [String]
    private let sounds: [String: [String]]

    static let alternateExtensions = ["m4a", "caf"]

    init(directory: URL?) {
        self.directory = directory
        func json(_ name: String) -> [String: Any] {
            guard let url = directory?.appending(path: name), let data = try? Data(contentsOf: url) else { return [:] }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        }
        music = json("music.json").compactMapValues { ($0 as? [String])?.map { "music/\($0)" } }
        sounds = json("sounds.json").compactMapValues { ($0 as? [String])?.map { "sounds/\($0)" } }

        var base: [String: [String]] = [:]
        var overlays: [String: [String]] = [:]
        var menu: [String] = []
        for (key, value) in json("ambiance.json") {
            if key == "menu_playlist" {
                menu = (value as? [String] ?? []).map { "ambiance/\($0)" }
                continue
            }
            for (name, tracks) in value as? [String: [String]] ?? [:] {
                let paths = tracks.map { "ambiance/\($0)" }
                if name == "base" { base[key] = paths } else { overlays[name] = paths }
            }
        }
        ambienceBase = base
        self.overlays = overlays
        menuAmbience = menu
    }

    static let bundled = AudioLibrary(directory: Bundle.main.url(forResource: "Audio", withExtension: nil))

    /// Clangen's `find_playlist`: the menu playlist, or the general playlist plus any for the season and biome.
    func musicPlaylist(for scene: AudioScene) -> [String] {
        switch scene {
        case .menu:
            return music["menu_playlist"] ?? []
        case let .clan(biome, _, season):
            let seasonKey = season.rawValue.lowercased().replacing("-", with: "")
            return (music["general_playlist"] ?? []) + (music["\(seasonKey)_playlist"] ?? []) + (music["\(biome.key)_playlist"] ?? [])
        }
    }

    /// The long ambience that plays continuously: the menu's, or the biome's base tracks.
    func ambienceBase(for scene: AudioScene) -> [String] {
        switch scene {
        case .menu: menuAmbience
        case let .clan(biome, _, _): ambienceBase[Self.ambienceKey(biome)] ?? []
        }
    }

    /// Clangen has no Wetlands or Desert ambience; they borrow the nearest biome's.
    private static func ambienceKey(_ biome: Biome) -> String {
        switch biome {
        case .wetlands: Biome.beach.key
        case .desert: Biome.plains.key
        default: biome.key
        }
    }

    /// Short sounds for the camp, e.g. waves at Lakeside, played now and then over the base.
    /// Borrowed camps keep the sounds of the camp whose art they use.
    func campOverlays(biome: Biome, camp: Int) -> [String] {
        let source = CampLibrary.artSource(biome: biome, camp: camp)
        guard source.biome.campNames.indices.contains(source.camp - 1) else { return [] }
        return overlays[source.biome.campNames[source.camp - 1].lowercased().replacing(" ", with: "_")] ?? []
    }

    func seasonOverlays(_ season: Season) -> [String] {
        overlays[season.rawValue.lowercased()] ?? []
    }

    func sounds(_ effect: SoundEffect) -> [String] {
        sounds[effect.rawValue] ?? []
    }

    /// The file for a track, or nil when it isn't bundled.
    func url(_ path: String) -> URL? {
        guard let directory else { return nil }
        let exact = directory.appending(path: path)
        let base = exact.deletingPathExtension()
        let candidates = [exact] + Self.alternateExtensions.map { base.appendingPathExtension($0) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    /// The tracks of a playlist whose files are present.
    func available(_ playlist: [String]) -> [String] {
        playlist.filter { url($0) != nil }
    }

    /// Whether any music, ambience or sound file is present.
    var hasAudioFiles: Bool {
        let lists: [[String]] = Array(music.values) + Array(ambienceBase.values) + Array(overlays.values) + [menuAmbience] + Array(sounds.values)
        return lists.contains { $0.contains { url($0) != nil } }
    }

    /// Clangen's `choose`: a random track, avoiding the last one played when there's a choice.
    static func nextTrack(from playlist: [String], after last: String?, using rng: inout some RandomNumberGenerator) -> String? {
        guard playlist.count > 1 else { return playlist.first }
        let options = playlist.filter { $0 != last }
        return (options.isEmpty ? playlist : options).randomElement(using: &rng)
    }
}
