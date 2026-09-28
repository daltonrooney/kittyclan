import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum State {
        case loading
        case failed(String)
        case founding(FoundingModel)
        case playing
    }

    private(set) var state = State.loading
    private(set) var assets: GameAssets?
    private(set) var clan: Clan?
    private(set) var isAdvancing = false
    private(set) var latestMoon: Int?
    var errorMessage: String?
    var selectedCat: Cat?
    var patrol: PatrolModel?
    var isShowingSupplies = false
    var isShowingLeaderDen = false
    var leaderDenTab = LeaderDenTab.clans

    @ObservationIgnored private(set) var sprites: SpriteCache?
    @ObservationIgnored private let store: ClanStore

    init(store: ClanStore = .standard) {
        self.store = store
    }

    func load() async {
        guard assets == nil else { return }
        do {
            let assets = try await Self.loadAssets()
            self.assets = assets
            sprites = SpriteCache(assets: assets)
            if let saved = try await store.load() {
                clan = saved
                state = .playing
            } else {
                state = .founding(FoundingModel(assets: assets))
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func found(from founding: FoundingModel) async {
        guard let newClan = founding.makeClan() else { return }
        clan = newClan
        latestMoon = nil
        state = .playing
        await save()
    }

    func timeskip() async {
        guard let assets, let current = clan, !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        let advanced = await Self.advance(current, moons: 1, engine: assets.engine)
        clan = advanced
        latestMoon = advanced.age
        await save()
    }

    /// Cats who can still go on patrol this moon.
    var patrolEligible: [Cat] {
        clan.map(PatrolEngine.eligible) ?? []
    }

    func beginPatrol() {
        patrol = PatrolModel(app: self)
    }

    /// Picks a patrol for these cats and saves the Clan. Returns nil when no patrol fits them.
    func startPatrol(_ catIDs: [Cat.ID], type: PatrolType?) async -> PatrolSession? {
        guard let assets, let current = clan, !isAdvancing else { return nil }
        isAdvancing = true
        defer { isAdvancing = false }
        let (updated, session) = await Self.startPatrol(catIDs, type: type, in: current, engine: assets.patrols)
        guard let session else { return nil }
        clan = updated
        await save()
        return session
    }

    /// Resolves the player's choice on a patrol and saves the Clan.
    func finishPatrol(_ session: PatrolSession, choice: PatrolChoice) async -> PatrolResult? {
        guard let assets, let current = clan, !isAdvancing else { return nil }
        isAdvancing = true
        defer { isAdvancing = false }
        let (updated, result) = await Self.finishPatrol(session, choice: choice, in: current, engine: assets.patrols)
        clan = updated
        await save()
        return result
    }

    /// Feeds these cats from the fresh-kill pile and saves the Clan.
    func feed(_ catIDs: [Cat.ID]) async {
        guard let assets, let current = clan, current.preyAndHerbs, !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        clan = await Self.feed(catIDs, in: current, engine: assets.engine)
        await save()
    }

    // MARK: - Other Clans and outsiders

    /// Who makes this moon's leader's den choices, if anyone can.
    var leaderDenActor: Cat? {
        clan.flatMap(MoonEngine.leaderDenActor)
    }

    /// Clangen only lets a living leader (or a helper standing in for a sick one) deal with outsiders.
    var canPlanForOutsiders: Bool {
        guard let clan else { return false }
        return clan.isAlive(clan.leader) && leaderDenActor != nil
    }

    /// The player Clan's temperament as the other Clans see it, e.g. "wary & eager".
    var clanTemperament: String {
        clan.map { MoonEngine.temperament(of: $0).joined(separator: " & ") } ?? ""
    }

    /// Living outsiders the Clan knows of and who are still nearby.
    var nearbyOutsiders: [Cat] {
        clan?.outsiders.filter { $0.isAlive && $0.isNear } ?? []
    }

    var denOutsiders: [Cat] {
        clan.map(MoonEngine.denOutsiders) ?? []
    }

    func isOutsider(_ cat: Cat) -> Bool {
        clan?.outsiders.contains { $0.id == cat.id } ?? false
    }

    var enemyClan: OtherClan? {
        clan?.otherClan(clan?.war.enemy)
    }

    /// Queues a leader's den choice for next moon, replacing any earlier choice of the same kind.
    func planLeaderDen(_ action: DenAction, target: LeaderDenPlan.Target) async {
        guard let assets, let current = clan, !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        clan = await Self.planLeaderDen(action.rawValue, target: target, in: current, engine: assets.engine)
        await save()
    }

    /// Clangen's wording for a queued choice, e.g. "Pinestar has decided to befriend RiverClan."
    func planText(_ plan: LeaderDenPlan) -> String? {
        guard let clan, let action = DenAction(rawValue: plan.interaction) else { return nil }
        let actor = clan[plan.actor].map(displayName) ?? "The leader"
        let target: String? = switch plan.target {
        case .clan(let id): clan.otherClan(id)?.name
        case .outsider(let id): clan[id].map(displayName)
        }
        guard let target else { return nil }
        return "\(actor) has decided to \(action.phrase(target))."
    }

    /// Sends a living Clan cat away as an exiled loner and closes their profile.
    func exile(_ id: Cat.ID) async {
        guard let assets, let current = clan, current.isAlive(id), !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        clan = await Self.exile(id, in: current, engine: assets.engine)
        selectedCat = nil
        await save()
    }

    func patrolArtURL(_ name: String?) -> URL? {
        assets?.patrols.library.artURL(name)
    }

    func conditionName(_ condition: CatCondition) -> String {
        let name = assets?.engine.conditions?.displayName(condition.name) ?? condition.name
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// This cat's non-neutral feelings toward living Clan cats, strongest first.
    func relationships(of cat: Cat) -> [CatRelationshipEntry] {
        guard let clan, let feelings = clan.relationships[cat.id] else { return [] }
        let living = Dictionary(uniqueKeysWithValues: clan.living.map { ($0.id, $0) })
        return feelings
            .compactMap { id, relationship in
                guard id != cat.id, !relationship.isNeutral, let other = living[id] else { return nil }
                return CatRelationshipEntry(cat: other, relationship: relationship)
            }
            .sorted { $0.relationship.totalMagnitude > $1.relationship.totalMagnitude }
    }

    // MARK: - Skills and supplies

    /// Clangen's profile wording, e.g. "great hunter & fledgeling storyteller".
    func skills(of cat: Cat) -> String {
        assets?.skillText.describe(cat) ?? ""
    }

    /// The short form for lists, e.g. "hunting & storytelling".
    func shortSkills(of cat: Cat) -> String {
        assets?.skillText.short(cat) ?? ""
    }

    var preyNeeded: Double {
        clan.map(MoonEngine.preyNeeded) ?? 0
    }

    var isLowOnPrey: Bool {
        guard let clan, clan.preyAndHerbs else { return false }
        return clan.freshKill.total < preyNeeded
    }

    func nutrition(of cat: Cat) -> Nutrition? {
        guard let clan, clan.preyAndHerbs, cat.isAlive else { return nil }
        return clan.nutrition[cat.id]
    }

    /// Living cats who aren't fully fed, hungriest first.
    var hungryCats: [HungryCat] {
        guard let clan, clan.preyAndHerbs else { return [] }
        return clan.living
            .compactMap { cat in
                guard let nutrition = clan.nutrition[cat.id], nutrition.percentage < 100 else { return nil }
                return HungryCat(cat: cat, nutrition: nutrition)
            }
            .sorted { $0.nutrition.percentage < $1.nutrition.percentage }
    }

    /// Herbs in the medicine den, in the library's order.
    var herbStock: [HerbStock] {
        guard let clan, let library = assets?.engine.herbLibrary else { return [] }
        let size = clan.living.count
        return library.herbs.compactMap { herb in
            let count = clan.herbs.total(of: herb.name)
            guard count > 0 else { return nil }
            return HerbStock(
                id: herb.name,
                name: library.name(herb.name, count: count),
                count: count,
                rating: HerbSupply.rating(count, clanSize: size)
            )
        }
    }

    var herbRating: String? {
        guard let clan, let library = assets?.engine.herbLibrary else { return nil }
        return clan.herbs.overallRating(herbs: library.herbs.map(\.name), clanSize: clan.living.count)
    }

    /// The medicine cat's view of the herb stores this moon, if the Clan has one.
    var herbStatus: String? {
        guard let assets, let clan, let rating = herbRating,
              let healer = clan.living.first(where: { $0.rank == .medicineCat }),
              let lines = assets.engine.herbLibrary?.storageMessages[rating], !lines.isEmpty
        else { return nil }
        let line = lines[clan.age % lines.count]
        return assets.patrols.template.resolve(line, cats: ["m_c": healer], clan: clan)
    }

    func clearHighlight() {
        latestMoon = nil
    }

    func startNewClan() {
        guard let assets else { return }
        do {
            try store.delete()
        } catch {
            errorMessage = "Couldn't delete the old Clan: \(error.localizedDescription)"
        }
        clan = nil
        latestMoon = nil
        selectedCat = nil
        patrol = nil
        isShowingLeaderDen = false
        state = .founding(FoundingModel(assets: assets))
    }

    func displayName(_ cat: Cat) -> String {
        assets?.displayName(cat) ?? cat.name.prefix
    }

    func cat(_ id: Cat.ID?) -> Cat? {
        clan?[id]
    }

    func cats(_ ids: [Cat.ID]) -> [Cat] {
        ids.compactMap { clan?[$0] }
    }

    func kits(of cat: Cat) -> [Cat] {
        clan?.cats.filter { $0.parents.contains(cat.id) } ?? []
    }

    func lifeStory(of cat: Cat) -> [LifeEvent] {
        clan?.history.flatMap { log in
            log.entries.filter { $0.cats.contains(cat.id) }.map { LifeEvent(moon: log.moon, entry: $0) }
        } ?? []
    }

    private func save() async {
        guard let clan else { return }
        do {
            try await store.save(clan)
        } catch {
            errorMessage = "Couldn't save your Clan: \(error.localizedDescription)"
        }
    }

    @concurrent
    private static func loadAssets() async throws -> GameAssets {
        try GameAssets.loadBundled()
    }

    @concurrent
    private static func advance(_ clan: Clan, moons: Int, engine: MoonEngine) async -> Clan {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<moons { engine.advance(&clan, using: &rng) }
        return clan
    }

    @concurrent
    private static func planLeaderDen(_ action: String, target: LeaderDenPlan.Target, in clan: Clan, engine: MoonEngine) async -> Clan {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        engine.planLeaderDen(action, target: target, in: &clan, using: &rng)
        return clan
    }

    @concurrent
    private static func exile(_ id: Cat.ID, in clan: Clan, engine: MoonEngine) async -> Clan {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        engine.exileCat(id, in: &clan, using: &rng)
        return clan
    }

    @concurrent
    private static func feed(_ catIDs: [Cat.ID], in clan: Clan, engine: MoonEngine) async -> Clan {
        var clan = clan
        engine.feed(catIDs, in: &clan, manual: true)
        return clan
    }

    @concurrent
    private static func startPatrol(_ catIDs: [Cat.ID], type: PatrolType?, in clan: Clan, engine: PatrolEngine) async -> (Clan, PatrolSession?) {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        let session = engine.start(catIDs, type: type, in: &clan, using: &rng)
        return (clan, session)
    }

    @concurrent
    private static func finishPatrol(_ session: PatrolSession, choice: PatrolChoice, in clan: Clan, engine: PatrolEngine) async -> (Clan, PatrolResult) {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        let result = engine.finish(session, choice: choice, in: &clan, using: &rng)
        return (clan, result)
    }
}

#if DEBUG
extension AppModel {
    /// Launch arguments for reaching screens without taps: `-autofound YES` (`-classic YES` founds
    /// without prey and herbs), `-timeskips N`, `-foundingStep cats|options`, `-autopick YES`,
    /// `-supplies YES|herbs` (opens the supplies sheet, optionally at the medicine den), `-feed YES` (feeds hungry cats), `-patrol hunting|border|training|herb_gathering|any`
    /// (picks cats and starts a patrol), `-patrolPickOnly YES` (stops at cat picking),
    /// `-patrolResult YES` (proceeds to the result), `-war YES` (starts a war with the first neighbour),
    /// `-outsiders YES` (exiles and loses a warrior if there are few outsiders, and expands the list),
    /// `-leaderDen clans|outsiders` (opens the leader's den), `-leaderDenPlan YES` (queues a choice for each tab).
    func applyDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        guard let assets else { return }

        if defaults.bool(forKey: "autofound") {
            let founding = FoundingModel(assets: assets)
            founding.autopick()
            founding.preyAndHerbs = !defaults.bool(forKey: "classic")
            await found(from: founding)
        } else if case .founding(let founding) = state {
            switch defaults.string(forKey: "foundingStep") {
            case "cats":
                founding.randomName()
                founding.showCats()
            case "options":
                founding.autopick()
                founding.showOptions()
            default:
                break
            }
            if defaults.bool(forKey: "autopick") { founding.autopick() }
        }

        let moons = defaults.integer(forKey: "timeskips")
        if moons > 0, let current = clan {
            clan = await Self.advance(current, moons: moons, engine: assets.engine)
            latestMoon = clan?.age
            await save()
        }

        await debugOtherClans()
        if defaults.bool(forKey: "feed") { await feed(hungryCats.map(\.id)) }
        selectedCat = debugCatToShow
        isShowingSupplies = defaults.string(forKey: "supplies") != nil
        await debugPatrol()
    }

    private func debugOtherClans() async {
        let defaults = UserDefaults.standard
        guard let assets else { return }
        if defaults.bool(forKey: "war"), let current = clan, !current.war.atWar, !current.otherClans.isEmpty {
            var advanced = current.age > 4 ? current : await Self.advance(current, moons: 5 - current.age, engine: assets.engine)
            advanced.otherClans[0].setRelations(0)
            advanced = await Self.advance(advanced, moons: 1, engine: assets.engine)
            clan = advanced
            latestMoon = advanced.age
        }
        if defaults.bool(forKey: "outsiders"), var current = clan, current.outsiders.filter(\.isAlive).count < 2 {
            var rng = SystemRandomNumberGenerator()
            let warriors = current.living.filter { $0.rank == .warrior }
            if let exiled = warriors.first { assets.engine.exileCat(exiled.id, in: &current, using: &rng) }
            if warriors.count > 1 { assets.engine.loseCat(warriors[1].id, in: &current, using: &rng) }
            clan = current
        }
        if defaults.bool(forKey: "leaderDenPlan"), let current = clan {
            if let other = current.otherClans.first, let action = DenAction(rawValue: MoonEngine.leaderDenActions(for: other.standing).1) {
                await planLeaderDen(action, target: .clan(other.id))
            }
            if let outsider = denOutsiders.first(where: { $0.age != .newborn }),
               let action = MoonEngine.outsiderActions(for: outsider).last.flatMap(DenAction.init(rawValue:)) {
                await planLeaderDen(action, target: .outsider(outsider.id))
            }
        }
        if let tab = defaults.string(forKey: "leaderDen") {
            leaderDenTab = LeaderDenTab(rawValue: tab) ?? .clans
            isShowingLeaderDen = true
        }
        await save()
    }

    private func debugPatrol() async {
        let defaults = UserDefaults.standard
        guard let request = defaults.string(forKey: "patrol") else { return }
        beginPatrol()
        guard let patrol else { return }
        patrol.selectType(PatrolType(rawValue: request))
        patrol.addRandom(3)
        guard !defaults.bool(forKey: "patrolPickOnly") else { return }
        await patrol.start()
        if defaults.bool(forKey: "patrolResult") { await patrol.choose(.proceed) }
    }

    /// `-showCat first` opens the leader; `-showCat outsider` opens the first nearby outsider; `-showCat sick` opens the cat with the most known conditions; any other value opens the first cat whose name starts with it.
    var debugCatToShow: Cat? {
        guard let query = UserDefaults.standard.string(forKey: "showCat"), let clan else { return nil }
        if query == "first" { return clan[clan.leader] ?? clan.living.first }
        if query == "outsider" { return nearbyOutsiders.first }
        if query == "sick" {
            return clan.living.max { $0.visibleConditions.count < $1.visibleConditions.count }
        }
        return clan.cats.first { displayName($0).lowercased().hasPrefix(query.lowercased()) }
    }
}
#endif
