import Foundation

/// A related cat shown in a cat's Family & Mentorship section.
struct CatRelation: Identifiable {
    let label: String
    let cat: Cat

    var id: String { "\(label)-\(cat.id)" }
}
