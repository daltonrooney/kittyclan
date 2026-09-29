import Foundation
import Compression
import os

enum SpriteError: Error, CustomStringConvertible {
    case missingSheet(String)
    case unsupportedPixelFormat(String)
    case unknownSprite(sheet: String, name: String)

    var description: String {
        switch self {
        case .missingSheet(let s): "Missing sprite sheet \(s)"
        case .unsupportedPixelFormat(let s): "\(s) could not be decoded"
        case .unknownSprite(let sheet, let name): "No sprite \(name) in \(sheet)"
        }
    }
}

/// Slices 50×50 cells out of Clangen's sprite sheets, including generated patch combos
/// and palette-recoloured collars.
///
/// A sheet is a grid of groups, each 4×8 cells (one per pose index). Decoded sheets are
/// large, so they live in a purgeable cache while sliced cells are kept.
final class SpriteAtlas: @unchecked Sendable {
    let index: SpriteIndex
    private let directory: URL
    private let positions: [String: [String: (row: Int, col: Int)]]
    private let sheets = NSCache<NSString, DecodedSheet>()
    private let cells = OSAllocatedUnfairLock(initialState: [String: PixelBuffer]())

    private static let whiteCategories = ["little", "mid", "high", "mostly"]

    init(directory: URL) throws {
        self.directory = directory
        index = try SpriteIndex.load(from: directory)
        positions = index.sheets.mapValues { entries in
            Dictionary(entries.map { ($0.name, (row: $0.row, col: $0.col)) }, uniquingKeysWith: { a, _ in a })
        }
        sheets.totalCostLimit = 120 * 1024 * 1024
    }

    static func bundled() throws -> SpriteAtlas {
        guard let url = Bundle.main.url(forResource: "Sprites", withExtension: nil) else {
            throw SpriteError.missingSheet("Sprites directory")
        }
        return try SpriteAtlas(directory: url)
    }

    /// The sprite `name` at `pose` from `sheet`, e.g. `sprite("eyes", "YELLOW", pose: 16)`.
    /// White-patch and tortie-patch combos are assembled from their parts.
    func sprite(_ sheet: String, _ name: String, pose: Int) throws -> PixelBuffer {
        let key = "\(sheet)|\(name)|\(pose)"
        if let cached = cells.withLock({ $0[key] }) { return cached }

        let cell: PixelBuffer
        if let parts = comboParts(sheet: sheet, name: name) {
            var combined = PixelBuffer()
            for (partSheet, partName) in parts {
                combined.blit(try sprite(partSheet, partName, pose: pose))
            }
            cell = combined
        } else if sheet == "acc_collars", let style = index.collarStyle(of: name) {
            let colour = style.colours[String(name.dropFirst(style.style.count + 1))]!
            var recoloured = try slice(sheet: sheet, row: style.row, col: style.col, pose: pose)
            recoloured.replaceExact(style.base, with: colour)
            cell = recoloured
        } else {
            guard let position = positions[sheet]?[name] else {
                throw SpriteError.unknownSprite(sheet: sheet, name: name)
            }
            cell = try slice(sheet: sheet, row: position.row, col: position.col, pose: pose)
        }
        cells.withLock { $0[key] = cell }
        return cell
    }

    private func comboParts(sheet: String, name: String) -> [(String, String)]? {
        if sheet == "patches_tortie", let parts = index.tortiePatchCombos[name] {
            return parts.map { ("patches_tortie", $0) }
        }
        guard sheet.hasPrefix("patches_white_") else { return nil }
        let category = String(sheet.dropFirst("patches_white_".count))
        guard let parts = index.whitePatchCombos[category + name] else { return nil }
        return parts.map { part in
            let partCategory = Self.whiteCategories.first { part.hasPrefix($0) } ?? category
            return ("patches_white_" + partCategory, String(part.dropFirst(partCategory.count)))
        }
    }

    private func slice(sheet: String, row: Int, col: Int, pose: Int) throws -> PixelBuffer {
        let decoded = try decodedSheet(sheet)
        let size = PixelBuffer.cellSize
        let originX = col * 4 * size + (pose % 4) * size
        let originY = row * 8 * size + (pose / 4) * size
        var cell = PixelBuffer()
        guard originX + size <= decoded.width, originY + size <= decoded.height else { return cell }
        decoded.bytes.withUnsafeBufferPointer { src in
            cell.bytes.withUnsafeMutableBufferPointer { dst in
                for y in 0..<size {
                    let s = ((originY + y) * decoded.width + originX) * 4
                    let d = y * size * 4
                    for i in 0..<(size * 4) { dst[d + i] = src[s + i] }
                }
            }
        }
        return cell
    }

    private func decodedSheet(_ sheet: String) throws -> DecodedSheet {
        if let cached = sheets.object(forKey: sheet as NSString) { return cached }
        let decoded = try DecodedSheet(url: directory.appending(path: "\(sheet).rgba"), name: sheet)
        sheets.setObject(decoded, forKey: sheet as NSString, cost: decoded.bytes.count)
        return decoded
    }
}

final class DecodedSheet {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// Reads an `.rgba` file written by `tools/export_assets.py`: little-endian UInt32
    /// width and height, then raw-DEFLATE-compressed straight-alpha RGBA8.
    init(url: URL, name: String) throws {
        guard let data = try? Data(contentsOf: url), data.count > 8 else { throw SpriteError.missingSheet(name) }
        let header = data.prefix(8).withUnsafeBytes { ($0.loadUnaligned(as: UInt32.self), $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        width = Int(UInt32(littleEndian: header.0))
        height = Int(UInt32(littleEndian: header.1))
        let expected = width * height * 4
        var pixels = [UInt8](repeating: 0, count: expected)
        let written = data.dropFirst(8).withUnsafeBytes { src in
            pixels.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(
                    dst.baseAddress!, expected,
                    src.bindMemory(to: UInt8.self).baseAddress!, src.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expected else { throw SpriteError.unsupportedPixelFormat(name) }
        bytes = pixels
    }

    var pixelBuffer: PixelBuffer { PixelBuffer(width: width, height: height, bytes: bytes) }
}
