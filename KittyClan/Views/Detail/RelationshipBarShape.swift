import SwiftUI

/// The filled part of a relationship bar. `fraction` runs −1…1 when centred, 0…1 otherwise.
struct RelationshipBarShape: Shape {
    var fraction: Double
    var isCentred: Bool

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(fraction, isCentred ? -1 : 0), 1)
        let origin = isCentred ? rect.midX : rect.minX
        let span = isCentred ? rect.width / 2 : rect.width
        let end = origin + span * clamped
        let bar = CGRect(x: min(origin, end), y: rect.minY, width: abs(end - origin), height: rect.height)
        return Path(roundedRect: bar, cornerRadius: rect.height / 2)
    }
}
