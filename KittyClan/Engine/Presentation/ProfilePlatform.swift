import Foundation

/// The ground Clangen draws behind a cat on its profile (`get_platform`), a cell of `platforms.png`.
/// Each row is a place and holds a dark and a light variant per season or afterlife.
struct ProfilePlatform: Hashable, Sendable {
    static let size = (width: 80, height: 70)
    /// Where the 50×50 sprite sits on the platform, in platform pixels.
    static let spriteOrigin = (x: 15, y: 0)

    private static let rows = ["beach", "forest", "mountainous", "nest", "plains", "dead"]

    let column: Int
    let row: Int

    /// Newborns and cats too sick or hurt to work rest on a nest; afterlife cats stand in their afterlife.
    init(biome: Biome, season: Season, nest: Bool, afterlife: Afterlife?, dark: Bool) {
        let offset = dark ? 0 : 1
        if let afterlife {
            row = Self.rows.firstIndex(of: "dead")!
            let place = switch afterlife {
            case .darkForest: 0
            case .starClan: 2
            case .unknownResidence: 4
            }
            column = place + offset
        } else {
            row = Self.rows.firstIndex(of: nest ? "nest" : Self.platformKey(biome))!
            let place = switch season {
            case .greenleaf: 0
            case .leafBare: 2
            case .leafFall: 4
            case .newleaf: 6
            }
            column = place + offset
        }
    }

    /// `platforms.png` has no Wetlands or Desert row: wetlands stand in the plains' reeds, desert on mountain rock.
    private static func platformKey(_ biome: Biome) -> String {
        switch biome {
        case .wetlands: Biome.plains.key
        case .desert: Biome.mountainous.key
        default: biome.key
        }
    }

    init(for cat: Cat, in clan: Clan, dark: Bool) {
        self.init(
            biome: clan.biome, season: clan.season,
            nest: cat.age == .newborn || cat.isNotWorking,
            afterlife: cat.isDead ? cat.afterlife : nil,
            dark: dark
        )
    }

    /// The cell's rectangle in `platforms.png`.
    var rect: CGRect {
        CGRect(x: column * Self.size.width, y: row * Self.size.height, width: Self.size.width, height: Self.size.height)
    }
}
