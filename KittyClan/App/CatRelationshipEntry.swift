import Foundation

/// How one cat feels about another Clan cat.
struct CatRelationshipEntry: Identifiable {
    let cat: Cat
    let relationship: Relationship

    var id: Cat.ID { cat.id }
}
