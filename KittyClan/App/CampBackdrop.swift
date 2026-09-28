import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

/// A decoded camp background plus its average colour in 25-point cells of the camp canvas,
/// used to tint cats with the light around them the way Clangen does.
struct CampBackdrop: Sendable {
    static let cell = 25.0

    let image: CGImage
    private let columns: Int
    private let rows: Int
    private let cells: [SIMD3<Double>]

    /// Clangen blends about 22% of the blurred background under each cat.
    static let shadeStrength = 1 - 200.0 / 255

    @concurrent
    static func load(_ url: URL) async -> CampBackdrop? {
        guard let image = decode(url) else { return nil }
        return CampBackdrop(image: image)
    }

    @concurrent
    static func loadImage(_ url: URL) async -> CGImage? {
        decode(url)
    }

    private static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private init?(image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        let canvas = CampLayout.canvas
        let columns = Int(canvas.width / Self.cell)
        let rows = Int(canvas.height / Self.cell)
        let scaleX = Double(width) / canvas.width
        let scaleY = Double(height) / canvas.height
        var cells: [SIMD3<Double>] = []
        cells.reserveCapacity(columns * rows)
        for row in 0..<rows {
            let y0 = Int(Double(row) * Self.cell * scaleY)
            let y1 = max(y0 + 1, min(height, Int(Double(row + 1) * Self.cell * scaleY)))
            for column in 0..<columns {
                let x0 = Int(Double(column) * Self.cell * scaleX)
                let x1 = max(x0 + 1, min(width, Int(Double(column + 1) * Self.cell * scaleX)))
                var sum = SIMD3<Double>()
                var weight = 0.0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        let i = (y * width + x) * 4
                        let alpha = Double(pixels[i + 3])
                        guard alpha > 0 else { continue }
                        sum += SIMD3(Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2]))
                        weight += alpha
                    }
                }
                cells.append(weight > 0 ? sum / weight : SIMD3())
            }
        }
        self.image = image
        self.columns = columns
        self.rows = rows
        self.cells = cells
    }

    /// The average background colour under a 50×50 sprite whose top-left is at `point`.
    func shade(at point: CGPoint) -> Color {
        let first = (column: Int(point.x / Self.cell), row: Int(point.y / Self.cell))
        var sum = SIMD3<Double>()
        var count = 0.0
        for row in first.row...(first.row + 2) where (0..<rows).contains(row) {
            for column in first.column...(first.column + 2) where (0..<columns).contains(column) {
                sum += cells[row * columns + column]
                count += 1
            }
        }
        guard count > 0 else { return .clear }
        let average = sum / count
        return Color(red: average.x, green: average.y, blue: average.z)
    }
}
