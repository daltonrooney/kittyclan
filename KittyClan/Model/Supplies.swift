import Foundation

/// Clangen's fresh-kill pile: prey keeps for three moons.
struct FreshKillPile: Codable, Hashable, Sendable {
    /// Prey that expires after 3, 2 and 1 more moons.
    var expiresIn3 = 0.0
    var expiresIn2 = 0.0
    var expiresIn1 = 0.0
    /// What happened to the pile this moon, newest last.
    var log: [String] = []

    static let startingAmount = 60.0

    var total: Double { expiresIn3 + expiresIn2 + expiresIn1 }

    mutating func add(_ amount: Double) {
        expiresIn3 = ((expiresIn3 + amount) * 100).rounded() / 100
    }

    /// Takes from the oldest prey first. Returns how much was actually taken.
    @discardableResult
    mutating func take(_ amount: Double) -> Double {
        var needed = amount
        for path in [\FreshKillPile.expiresIn1, \.expiresIn2, \.expiresIn3] where needed > 0 {
            let taken = min(self[keyPath: path], needed)
            self[keyPath: path] -= taken
            needed -= taken
        }
        return amount - needed
    }

    /// Ages the pile a moon and returns how much prey spoiled.
    mutating func age() -> Double {
        let spoiled = expiresIn1
        expiresIn1 = expiresIn2
        expiresIn2 = expiresIn3
        expiresIn3 = 0
        return spoiled
    }
}

/// How well fed a cat is, as a score out of what it needs.
struct Nutrition: Codable, Hashable, Sendable {
    var maxScore: Double
    var currentScore: Double

    var percentage: Double { maxScore > 0 ? currentScore / maxScore * 100 : 100 }

    /// Clangen's nutrition words: starving, very hungry, hungry, satiated, full, stuffed.
    var label: String {
        let bounds: [(Double, String)] = [(91, "stuffed"), (81, "full"), (61, "satiated"), (41, "hungry"), (21, "very hungry")]
        return bounds.first { percentage >= $0.0 }?.1 ?? "starving"
    }
}

/// The medicine den's herb stores, in batches that expire.
struct HerbSupply: Codable, Hashable, Sendable {
    /// Herb → batches, newest first.
    var storage: [String: [Int]] = [:]
    /// Herbs gathered this moon, added to storage next moon but usable now.
    var collected: [String: Int] = [:]
    /// What happened in the medicine den this moon.
    var log: [String] = []

    func total(of herb: String) -> Int {
        (storage[herb] ?? []).reduce(0, +) + (collected[herb] ?? 0)
    }

    var total: Int { Set(storage.keys).union(collected.keys).reduce(0) { $0 + total(of: $1) } }

    mutating func add(_ herb: String, _ amount: Int) {
        guard amount > 0 else { return }
        collected[herb, default: 0] += amount
    }

    /// Uses the oldest herbs first.
    mutating func remove(_ herb: String, _ amount: Int) {
        var left = amount
        while left > 0, var batches = storage[herb], let oldest = batches.last {
            let used = min(oldest, left)
            left -= used
            if oldest - used == 0 { batches.removeLast() } else { batches[batches.count - 1] = oldest - used }
            storage[herb] = batches
        }
        if left > 0, let have = collected[herb] { collected[herb] = max(0, have - left) }
    }
}
