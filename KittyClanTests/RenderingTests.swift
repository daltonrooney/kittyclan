import CryptoKit
import XCTest
@testable import KittyClan

final class RenderingTests: XCTestCase {
    private static let golden = Bundle(for: RenderingTests.self).url(forResource: "Golden", withExtension: nil)!

    func testBlendMathMatchesPygame() throws {
        struct Op: Decodable { let flag: Int; let opacity: Int?; let result: [[Int]] }
        struct Cases: Decodable { let dst: [[Int]]; let src: [[Int]]; let ops: [String: Op] }
        let cases = try JSONDecoder().decode(Cases.self, from: Data(contentsOf: Self.golden.appending(path: "blend_cases.json")))

        let blends: [String: PixelBuffer.Blend] = [
            "normal": .normal, "normal_opacity_50": .normal(opacity: 50), "normal_opacity_33": .normal(opacity: 33),
            "rgba_mult": .maskRGBA, "rgb_mult": .multiplyRGB, "rgb_add": .addRGB, "rgb_sub": .subtractRGB, "rgba_min": .minRGBA,
        ]
        let n = cases.dst.count
        func buffer(_ pixels: [[Int]]) -> PixelBuffer {
            PixelBuffer(width: n, height: 1, bytes: pixels.flatMap { $0.map(UInt8.init) })
        }
        for (name, op) in cases.ops {
            let blend = try XCTUnwrap(blends[name], "unmapped op \(name)")
            var dst = buffer(cases.dst)
            dst.blit(buffer(cases.src), blend)
            let expected = buffer(op.result)
            for i in 0..<n where dst.bytes[i * 4..<i * 4 + 4] != expected.bytes[i * 4..<i * 4 + 4] {
                XCTFail("\(name) case \(i): dst \(cases.dst[i]) src \(cases.src[i]) → \(Array(dst.bytes[i * 4..<i * 4 + 4])), expected \(op.result[i])")
            }
        }
    }

    func testCatsMatchClangenRenders() throws {
        struct Fixture: Decodable {
            let id: String, pose: Int, name: String, colour: String, length: String
            let eyeColour: String, eyeColour2: String?
            let whitePatches: String?, points: String?, vitiligo: String?
            let tortieBase: String?, tortiePattern: String?, tortieColour: String?, tortieMarking: String?
            let skin: String, scars: [String], accessories: [String]
            let tint: String, whitePatchesTint: String?, reverse: Bool
        }
        let renderer = try CatRenderer.bundled()
        let index = renderer.atlas.index
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: Self.golden.appending(path: "cats.json")))

        var checked = 0
        for f in fixtures {
            let appearance = CatAppearance(
                pattern: f.name, colour: f.colour, length: PeltLength(rawValue: f.length)!,
                eyeColour: f.eyeColour, eyeColour2: f.eyeColour2,
                whitePatches: f.whitePatches, points: f.points, vitiligo: f.vitiligo,
                tortieBase: f.tortieBase, tortiePattern: f.tortiePattern, tortieColour: f.tortieColour, tortieMarking: f.tortieMarking,
                skin: f.skin, scars: f.scars, accessories: f.accessories,
                tint: f.tint, whitePatchesTint: f.whitePatchesTint, reverse: f.reverse, poses: [:]
            )
            let actual = try renderer.render(appearance, poseName: index.poses[f.pose])
            let expected = try DecodedSheet(url: Self.golden.appending(path: "\(f.id).rgba"), name: f.id).pixelBuffer

            var mismatches = 0
            var first: String?
            for i in stride(from: 0, to: actual.bytes.count, by: 4) {
                let a = Array(actual.bytes[i..<i + 4]), e = Array(expected.bytes[i..<i + 4])
                if a == e || (a[3] == 0 && e[3] == 0) { continue }
                mismatches += 1
                if first == nil { first = "pixel \(i / 4 % 50),\(i / 4 / 50): got \(a) expected \(e)" }
            }
            XCTAssertEqual(mismatches, 0, "\(f.id) (\(f.name) \(f.colour)): \(mismatches) pixels differ, first \(first ?? "")")
            checked += 1
        }
        XCTAssertEqual(checked, fixtures.count)
        XCTAssertGreaterThanOrEqual(checked, 68)
    }

    func testCollarCellsMatchClangenPalettes() throws {
        let atlas = try CatRenderer.bundled().atlas
        let index = atlas.index
        let expected = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.golden.appending(path: "collar_cells.json")))
        XCTAssertEqual(index.collars.count, 472)
        XCTAssertFalse(index.collars.contains("LEATHER_BELL_petal2"))
        XCTAssertEqual(Set(index.collars), Set(expected.keys))

        for id in index.collars {
            var hash = SHA256()
            for (pose, name) in index.poses.enumerated() where !name.isEmpty {
                hash.update(data: Data(try atlas.sprite("acc_collars", id, pose: pose).bytes))
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected[id], id)
        }
    }

    func testCollarsAreNamedByStyle() throws {
        let index = try CatRenderer.bundled().atlas.index
        XCTAssertEqual(index.collarStyle(of: "LEATHER_BELL_crimson1")?.style, "LEATHER_BELL")
        XCTAssertEqual(index.collarStyle(of: "LEATHER_BELL_SPIKE_white_gold2")?.style, "LEATHER_BELL_SPIKE")
        XCTAssertNil(index.collarStyle(of: "MAPLE LEAF"))
        XCTAssertEqual(index.accessoryName("LEATHER_BELL_crimson1"), "belled leather collar")
        XCTAssertEqual(index.accessoryName("PUFFBALL_DOUBLECOLOR_blue_white", form: \.many), "two-color puffball collars")
        XCTAssertEqual(index.accessoryName("MAPLE LEAF"), "maple leaf")
        for id in index.collars { XCTAssertEqual(index.accessoryBodyParts[id], "collar") }
    }

    func testGeneratedCatsAlwaysRender() throws {
        let assets = try GameAssets.loadBundled()
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let cat = assets.factory.make(rank: pick(Rank.allCases, &rng), using: &rng)
            for age in CatAge.allCases {
                do {
                    _ = try assets.renderer.render(cat.appearance, age: age)
                } catch {
                    return XCTFail("\(error) rendering \(cat.appearance)")
                }
            }
            XCTAssertFalse(assets.displayName(cat).isEmpty)
        }
    }
}
