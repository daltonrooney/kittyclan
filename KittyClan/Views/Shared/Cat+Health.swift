import Foundation

extension Cat {
    var isHealer: Bool { rank == .medicineCat || rank == .medicineApprentice }

    /// Conditions the Clan knows about; congenital conditions stay hidden until they show.
    var visibleConditions: [CatCondition] {
        conditions.filter(\.isRevealed)
    }

    var hasVisibleSickness: Bool { visibleConditions.contains { $0.kind != .permanent && !$0.isBirthCondition } }

    /// Pregnant or recovering from giving birth, which Clangen shows apart from other injuries.
    var hasBirthCondition: Bool { conditions.contains(where: \.isBirthCondition) }

    var hasVisiblePermanentCondition: Bool { visibleConditions.contains { $0.kind == .permanent } }
}
