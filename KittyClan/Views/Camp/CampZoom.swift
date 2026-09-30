import CoreGraphics

/// How far the camp canvas is zoomed, and which canvas point sits at the middle of the view.
struct CampZoom: Equatable {
    var scale: CGFloat
    var center: CGPoint

    /// Cats are 50 canvas points wide; this keeps them at least 44 points on screen.
    static let tappableScale: CGFloat = 0.9
    static let maximumScale: CGFloat = 2

    static func fitScale(in size: CGSize) -> CGFloat {
        min(size.width / CampLayout.canvas.width, size.height / CampLayout.canvas.height)
    }

    static func initial(in size: CGSize) -> CampZoom {
        CampZoom(
            scale: max(fitScale(in: size), tappableScale),
            center: CGPoint(x: CampLayout.canvas.width / 2, y: CampLayout.canvas.height / 2)
        )
    }

    func clamped(in size: CGSize) -> CampZoom {
        let fit = Self.fitScale(in: size)
        let scale = min(max(scale, fit), max(fit, Self.maximumScale))
        func clamp(_ value: CGFloat, visible: CGFloat, length: CGFloat) -> CGFloat {
            let half = visible / scale / 2
            return half * 2 >= length ? length / 2 : min(max(value, half), length - half)
        }
        return CampZoom(
            scale: scale,
            center: CGPoint(
                x: clamp(center.x, visible: size.width, length: CampLayout.canvas.width),
                y: clamp(center.y, visible: size.height, length: CampLayout.canvas.height)
            )
        )
    }

    func panned(by translation: CGSize) -> CampZoom {
        CampZoom(scale: scale, center: CGPoint(x: center.x - translation.width / scale, y: center.y - translation.height / scale))
    }

    /// Zooms so the canvas point under `anchor` (a point in the view) stays under it.
    func zoomed(by factor: CGFloat, around anchor: CGPoint, in size: CGSize) -> CampZoom {
        let target = min(max(scale * factor, Self.fitScale(in: size)), max(Self.fitScale(in: size), Self.maximumScale))
        let pinned = CGPoint(x: center.x + (anchor.x - size.width / 2) / scale, y: center.y + (anchor.y - size.height / 2) / scale)
        return CampZoom(
            scale: target,
            center: CGPoint(x: pinned.x - (anchor.x - size.width / 2) / target, y: pinned.y - (anchor.y - size.height / 2) / target)
        )
    }

    /// Where the canvas's top-left corner goes in the view.
    func offset(in size: CGSize) -> CGSize {
        CGSize(width: size.width / 2 - center.x * scale, height: size.height / 2 - center.y * scale)
    }
}
