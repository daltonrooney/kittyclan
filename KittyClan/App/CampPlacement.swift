import CoreGraphics

/// A cat's spot in camp: the top-left of its 50×50 sprite on the 800×700 camp canvas.
struct CampPlacement: Identifiable, Hashable {
    let id: Cat.ID
    let point: CGPoint
}
