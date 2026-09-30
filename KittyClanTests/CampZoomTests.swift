import XCTest
@testable import KittyClan

final class CampZoomTests: XCTestCase {
    private let phone = CGSize(width: 402, height: 520)
    private let pad = CGSize(width: 1000, height: 900)

    func testStartsZoomedForTappableCatsOnSmallScreens() {
        let zoom = CampZoom.initial(in: phone)
        XCTAssertGreaterThanOrEqual(50 * zoom.scale, 44)
        XCTAssertEqual(zoom.center, CGPoint(x: 400, y: 350))
    }

    func testStartsFittedOnLargeScreens() {
        let zoom = CampZoom.initial(in: pad)
        XCTAssertEqual(zoom.scale, CampZoom.fitScale(in: pad))
        XCTAssertEqual(zoom.offset(in: pad).width, (1000 - 800 * zoom.scale) / 2, accuracy: 0.001)
    }

    func testPanningStopsAtTheCanvasEdges() {
        let zoom = CampZoom.initial(in: phone).panned(by: CGSize(width: 5000, height: -5000)).clamped(in: phone)
        let offset = zoom.offset(in: phone)
        XCTAssertEqual(offset.width, 0, accuracy: 0.001)
        XCTAssertEqual(offset.height, phone.height - 700 * zoom.scale, accuracy: 0.001)
    }

    func testZoomIsClampedBetweenFitAndMaximum() {
        let start = CampZoom.initial(in: phone)
        let out = start.zoomed(by: 0.01, around: .zero, in: phone).clamped(in: phone)
        XCTAssertEqual(out.scale, CampZoom.fitScale(in: phone))
        XCTAssertEqual(out.center, CGPoint(x: 400, y: 350))
        let into = start.zoomed(by: 100, around: .zero, in: phone)
        XCTAssertEqual(into.scale, CampZoom.maximumScale)
    }

    func testPinchKeepsTheAnchoredPointInPlace() {
        let start = CampZoom(scale: 1, center: CGPoint(x: 400, y: 350))
        let anchor = CGPoint(x: 100, y: 100)
        let zoomed = start.zoomed(by: 1.5, around: anchor, in: phone)
        func canvasPoint(_ zoom: CampZoom) -> CGPoint {
            let offset = zoom.offset(in: phone)
            return CGPoint(x: (anchor.x - offset.width) / zoom.scale, y: (anchor.y - offset.height) / zoom.scale)
        }
        XCTAssertEqual(canvasPoint(start).x, canvasPoint(zoomed).x, accuracy: 0.001)
        XCTAssertEqual(canvasPoint(start).y, canvasPoint(zoomed).y, accuracy: 0.001)
    }
}
