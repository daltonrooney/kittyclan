import Foundation
import Observation

/// State for ClanGen's founding flow: name the Clan, then choose its cats.
@MainActor
@Observable
final class FoundingModel {
    enum Step: Hashable {
        case chooseCats
    }

    let assets: GameAssets
    var path: [Step] = []
    var name = "" {
        didSet {
            if name.count > ClanFounding.maxNameLength {
                name = String(name.prefix(ClanFounding.maxNameLength))
            }
        }
    }
    private(set) var candidates: [Cat] = []
    private(set) var selection = FoundingSelection()
    private(set) var rerollsLeft = ClanFounding.rerolls
    var notice: String?

    init(assets: GameAssets) {
        self.assets = assets
        var rng = SystemRandomNumberGenerator()
        candidates = assets.founding.candidates(using: &rng)
    }

    var isNameValid: Bool { ClanFounding.validateName(name) }
    var selectedCount: Int { selection.count }
    var isFull: Bool { selection.count >= ClanFounding.memberRange.upperBound }

    var canFound: Bool {
        selection.leader != nil && selection.deputy != nil && selection.medicineCat != nil
            && ClanFounding.memberRange.contains(selection.count)
    }

    var leader: Cat? { candidates.first { $0.id == selection.leader } }

    func role(of cat: Cat) -> ClanFounding.Role? {
        selection.role(of: cat.id)
    }

    func displayName(of cat: Cat) -> String {
        let rank = role(of: cat)?.displayRank(for: cat) ?? cat.rank
        return assets.names.display(cat.name, rank: rank)
    }

    func randomName() {
        var rng = SystemRandomNumberGenerator()
        name = assets.names.randomClanPrefix(excluding: name, using: &rng)
    }

    func showCats() {
        path = [.chooseCats]
    }

    func toggle(_ cat: Cat) {
        notice = nil
        if selection.role(of: cat.id) != nil {
            selection.remove(cat.id)
            return
        }
        guard !isFull else {
            notice = "Your Clan is full. Tap a chosen cat to let it go."
            return
        }
        let role = selection.nextRole
        guard !role.requiresExperience || ClanFounding.canLead(cat) else {
            notice = "\(displayName(of: cat)) is too young to be \(role.title.lowercased()). Pick an older cat first."
            return
        }
        selection.assign(cat.id, to: role)
    }

    func reroll() {
        guard rerollsLeft > 0 else { return }
        rerollsLeft -= 1
        selection = FoundingSelection()
        notice = nil
        var rng = SystemRandomNumberGenerator()
        candidates = assets.founding.candidates(using: &rng)
    }

    func makeClan() -> Clan? {
        guard canFound,
              let leader = cat(selection.leader),
              let deputy = cat(selection.deputy),
              let medicineCat = cat(selection.medicineCat)
        else { return nil }
        var rng = SystemRandomNumberGenerator()
        return assets.founding.found(
            prefix: name,
            leader: leader,
            deputy: deputy,
            medicineCat: medicineCat,
            members: selection.members.compactMap(cat),
            engine: assets.engine,
            using: &rng
        )
    }

    private func cat(_ id: Cat.ID?) -> Cat? {
        candidates.first { $0.id == id }
    }
}

#if DEBUG
extension FoundingModel {
    /// Picks a random valid Clan, rerolling candidates until three can hold the leading roles.
    func autopick(total: Int = 8) {
        if name.isEmpty { randomName() }
        var rng = SystemRandomNumberGenerator()
        while candidates.count(where: ClanFounding.canLead) < 3 {
            candidates = assets.founding.candidates(using: &rng)
        }
        selection = FoundingSelection()
        for cat in candidates.filter(ClanFounding.canLead).prefix(3) { toggle(cat) }
        for cat in candidates where selection.count < total && role(of: cat) == nil { toggle(cat) }
    }
}
#endif
