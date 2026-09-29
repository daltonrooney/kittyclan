import Foundation
import Observation

/// State for ClanGen's founding flow: name the Clan, choose its cats, its biome and camp, its symbol, then how it lives.
@MainActor
@Observable
final class FoundingModel {
    enum Step: Hashable {
        case chooseCats
        case biome
        case camp
        case symbol
        case options
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
    /// Clangen's expanded mode: a fresh-kill pile to keep full and herbs for healing.
    var preyAndHerbs = false {
        didSet { if !preyAndHerbs { canStarve = false } }
    }
    var canStarve = false
    /// Lets warriors and elders become mediators as they age.
    var becomeMediator = false
    var biome: Biome = .forest {
        didSet { if biome != oldValue { camp = 1 } }
    }
    /// Which of the biome's four camps the Clan settles in (1–4).
    var camp = 1
    /// The chosen Clan symbol's sprite id; nil until one is picked.
    var symbol: String?
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

    func showBiome() {
        guard canFound else { return }
        path = [.chooseCats, .biome]
    }

    func showCamp() {
        guard canFound else { return }
        path = [.chooseCats, .biome, .camp]
    }

    /// Clangen preselects the symbol drawn for the Clan's name, when there is one.
    func showSymbol() {
        guard canFound else { return }
        if symbol == nil { symbol = recommendedSymbol }
        path = [.chooseCats, .biome, .camp, .symbol]
    }

    func showOptions() {
        guard canFound else { return }
        path = [.chooseCats, .biome, .camp, .symbol, .options]
    }

    var recommendedSymbol: String? {
        ClanSymbols.bundled.recommended(forPrefix: name.trimmingCharacters(in: .whitespaces))
    }

    func randomSymbol() {
        var rng = SystemRandomNumberGenerator()
        symbol = ClanSymbols.bundled.random(using: &rng)
    }

    /// Clangen's `random_biome_selection`: another biome and any of its camps.
    func surpriseMe() {
        var rng = SystemRandomNumberGenerator()
        if let pick = Biome.allCases.filter({ $0 != biome }).randomElement(using: &rng) { biome = pick }
        camp = Int.random(in: 1...biome.campNames.count, using: &rng)
        showCamp()
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
        var clan = assets.founding.found(
            prefix: name,
            leader: leader,
            deputy: deputy,
            medicineCat: medicineCat,
            members: selection.members.compactMap(cat),
            preyAndHerbs: preyAndHerbs,
            canStarve: canStarve,
            biome: biome,
            camp: camp,
            engine: assets.engine,
            using: &rng
        )
        clan.becomeMediator = becomeMediator
        clan.symbol = symbol ?? ClanSymbols.bundled.fallback(forPrefix: clan.prefix, using: &rng)
        return clan
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
