import CoreGraphics
import Foundation

struct RGB: Hashable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8

    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF))
    }

    init?(components: [Int]?) {
        guard let c = components, c.count >= 3 else { return nil }
        self.init(UInt8(clamping: c[0]), UInt8(clamping: c[1]), UInt8(clamping: c[2]))
    }
}

/// A straight-alpha (non-premultiplied) RGBA8 image whose blend operations
/// reproduce pygame-ce's integer math, so composited sprites match Clangen exactly.
struct PixelBuffer: Equatable, Sendable {
    static let cellSize = 50

    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int = cellSize, height: Int = cellSize) {
        self.width = width
        self.height = height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 4)
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    static func fill(_ color: RGB, width: Int = cellSize, height: Int = cellSize) -> PixelBuffer {
        var buffer = PixelBuffer(width: width, height: height)
        for i in stride(from: 0, to: buffer.bytes.count, by: 4) {
            buffer.bytes[i] = color.r
            buffer.bytes[i + 1] = color.g
            buffer.bytes[i + 2] = color.b
            buffer.bytes[i + 3] = 255
        }
        return buffer
    }

    enum Blend: Sendable {
        /// pygame alpha blit, with surface opacity 0–100.
        case normal(opacity: Int)
        /// BLEND_RGBA_MULT
        case maskRGBA
        /// BLEND_RGB_MULT
        case multiplyRGB
        /// BLEND_RGB_ADD
        case addRGB
        /// BLEND_RGB_SUB
        case subtractRGB
        /// BLEND_RGBA_MIN
        case minRGBA

        static let normal = Blend.normal(opacity: 100)
    }

    mutating func blit(_ source: PixelBuffer, _ blend: Blend = .normal) {
        precondition(source.width == width && source.height == height)
        let count = bytes.count
        source.bytes.withUnsafeBufferPointer { s in
            bytes.withUnsafeMutableBufferPointer { d in
                switch blend {
                case .normal(let opacity):
                    let surfaceAlpha = opacity >= 100 ? 255 : Int(Double(opacity) * 2.55)
                    for i in stride(from: 0, to: count, by: 4) {
                        var sa = Int(s[i + 3])
                        if surfaceAlpha != 255 { sa = sa * surfaceAlpha / 255 }
                        let da = Int(d[i + 3])
                        if da == 0 {
                            d[i] = s[i]
                            d[i + 1] = s[i + 1]
                            d[i + 2] = s[i + 2]
                            d[i + 3] = UInt8(sa)
                            continue
                        }
                        for c in 0..<3 {
                            let sc = Int(s[i + c])
                            let dc = Int(d[i + c])
                            d[i + c] = UInt8(clamping: dc + (((sc - dc) * sa + sc) >> 8))
                        }
                        d[i + 3] = UInt8(clamping: sa + da - (sa * da) / 255)
                    }
                case .maskRGBA:
                    for i in 0..<count { d[i] = Self.multiply(d[i], s[i]) }
                case .multiplyRGB:
                    for i in stride(from: 0, to: count, by: 4) {
                        for c in 0..<3 { d[i + c] = Self.multiply(d[i + c], s[i + c]) }
                    }
                case .addRGB:
                    for i in stride(from: 0, to: count, by: 4) {
                        for c in 0..<3 { d[i + c] = UInt8(min(Int(d[i + c]) + Int(s[i + c]), 255)) }
                    }
                case .subtractRGB:
                    for i in stride(from: 0, to: count, by: 4) {
                        for c in 0..<3 { d[i + c] = UInt8(max(Int(d[i + c]) - Int(s[i + c]), 0)) }
                    }
                case .minRGBA:
                    for i in 0..<count { d[i] = min(d[i], s[i]) }
                }
            }
        }
    }

    /// Applies a solid, fully opaque colour with the given blend (tints).
    mutating func apply(_ color: RGB, _ blend: Blend) {
        blit(.fill(color, width: width, height: height), blend)
    }

    func flippedHorizontally() -> PixelBuffer {
        var out = self
        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + (width - 1 - x)) * 4
                let dst = (y * width + x) * 4
                for c in 0..<4 { out.bytes[dst + c] = bytes[src + c] }
            }
        }
        return out
    }

    func cgImage() -> CGImage? {
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        return provider.flatMap {
            CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: $0, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        }
    }

    @inline(__always)
    private static func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        a == 0 || b == 0 ? 0 : UInt8((Int(a) * Int(b) + 255) >> 8)
    }
}
