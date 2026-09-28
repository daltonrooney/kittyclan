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
    /// Launch arguments for reaching screens without taps: `-autofound YES`, `-timeskips N`,
    /// `-foundingStep cats`, `-autopick YES`, `-patrol hunting|border|training|herb_gathering|any`
    /// (picks cats and starts a patrol), `-patrolPickOnly YES` (stops at cat picking),
    /// `-patrolResult YES` (proceeds to the result).
    func applyDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        guard let assets else { return }

        if defaults.bool(forKey: "autofound") {
            let founding = FoundingModel(assets: assets)
            founding.autopick()
            await found(from: founding)
        } else if case .founding(let founding) = state {
            if defaults.string(forKey: "foundingStep") == "cats" {
                founding.randomName()
                founding.showCats()
            }
            if defaults.bool(forKey: "autopick") { founding.autopick() }
        }

        let moons = defaults.integer(forKey: "timeskips")
        if moons > 0, let current = clan {
            clan = await Self.advance(current, moons: moons, engine: assets.engine)
            latestMoon = clan?.age
            await save()
        }

        selectedCat = debugCatToShow
        await debugPatrol()
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

    /// `-showCat first` opens the leader; `-showCat sick` opens the cat with the most known conditions; any other value opens the first cat whose name starts with it.
    var debugCatToShow: Cat? {
        guard let query = UserDefaults.standard.string(forKey: "showCat"), let clan else { return nil }
        if query == "first" { return clan[clan.leader] ?? clan.living.first }
        if query == "sick" {
            return clan.living.max { $0.visibleConditions.count < $1.visibleConditions.count }
        }
        return clan.cats.first { displayName($0).lowercased().hasPrefix(query.lowercased()) }
    }
}
#endif
