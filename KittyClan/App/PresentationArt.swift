import CoreGraphics
import Foundation
import ImageIO

/// Clan symbols and profile platforms cut from Clangen's sheets, decoded once and cached.
@MainActor
final class PresentationArt {
    static let shared = PresentationArt()

    private lazy var symbolSheet = Self.decode("symbols.png")
    private lazy var platformSheet = Self.decode("platforms.png")
    private var symbols: [String: CGImage] = [:]
    private var platforms: [ProfilePlatform: CGImage] = [:]

    func symbol(_ id: String) -> CGImage? {
        if let cached = symbols[id] { return cached }
        let size = ClanSymbols.spriteSize
        guard let symbol = ClanSymbols.bundled.symbolOrDefault(id),
              let image = symbolSheet?.cropping(to: CGRect(x: symbol.column * size, y: symbol.row * size, width: size, height: size))
        else { return nil }
        symbols[id] = image
        return image
    }

    func platform(_ platform: ProfilePlatform) -> CGImage? {
        if let cached = platforms[platform] { return cached }
        guard let image = platformSheet?.cropping(to: platform.rect) else { return nil }
        platforms[platform] = image
        return image
    }

    private static func decode(_ name: String) -> CGImage? {
        guard let url = ClanSymbols.directory?.appending(path: name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
