import Foundation

/// A living cat who could eat more, for the supplies sheet.
struct HungryCat: Identifiable {
    let cat: Cat
    let nutrition: Nutrition

    var id: Cat.ID { cat.id }
}
