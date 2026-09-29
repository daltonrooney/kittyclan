import Foundation

/// One of the two cats a mediator works with.
enum MediationSlot: Int, CaseIterable, Identifiable {
    case first, second

    var id: Self { self }
    var title: String { self == .first ? "First cat" : "Second cat" }
    var other: Self { self == .first ? .second : .first }
}
