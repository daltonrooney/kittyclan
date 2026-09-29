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
    /// Scrolls the supplies sheet to the medicine den when it opens.
    var suppliesStartsAtHerbs = false
    var isShowingAbout = false
    var isShowingLeaderDen = false
    var leaderDenTab = LeaderDenTab.clans
    var isShowingAfterlife = false
    var afterlifeTab = Afterlife.starClan
    /// Where each living cat sits in camp, in draw order. Re-rolled on entering camp and after each moon, as in Clangen.
    private(set) var campPlacements: [CampPlacement] = []
    /// Living cats who didn't fit in camp at the last roll.
    private(set) var campOverflow = 0

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
        rollCamp()
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
        rollCamp()
        await save()
    }

    /// Clangen's camp placement for the living Clan cats. Newborns stay hidden in the nursery.
    func rollCamp() {
        guard let assets, let clan else {
            campPlacements = []
            campOverflow = 0
            return
        }
        var rng = SystemRandomNumberGenerator()
        let living = clan.living
        campPlacements = assets.camps.place(living, camp: clan.camp, using: &rng)
            .map { CampPlacement(id: $0.cat, point: $0.point) }
        campOverflow = max(0, living.count(where: { $0.rank != .newborn }) - campPlacements.count)
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
        rollCamp()
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
        rollCamp()
        await save()
    }

    // MARK: - Player controls

    /// Whether this is a living member of the Clan, who can have their role, mentor and mate changed.
    func isLivingClanCat(_ cat: Cat) -> Bool {
        clan?.isAlive(cat.id) ?? false
    }

    func roleTargets(for cat: Cat) -> [Rank] {
        guard let clan, clan.isAlive(cat.id) else { return [] }
        return cat.rank.manualTargets(leaderVacant: clan.leaderVacant, deputyVacant: clan.deputyVacant)
    }

    /// Changes a living cat's role. Making a leader also holds their nine-lives ceremony.
    @discardableResult
    func changeRank(_ rank: Rank, for id: Cat.ID) async -> Bool {
        guard let assets, let current = clan, !isAdvancing else { return false }
        isAdvancing = true
        defer { isAdvancing = false }
        let (updated, changed) = await Self.changeRank(rank, for: id, in: current, engine: assets.engine)
        guard changed else { return false }
        clan = updated
        rollCamp()
        await save()
        return true
    }

    func mentorCandidates(for cat: Cat, noCurrentApprentices: Bool, noFormerApprentices: Bool) -> [Cat] {
        guard let clan else { return [] }
        return MoonEngine.mentorCandidates(
            for: cat.id, in: clan, noCurrentApprentices: noCurrentApprentices, noFormerApprentices: noFormerApprentices
        )
    }

    /// Gives an apprentice a new mentor, or none until the next moon picks one.
    func setMentor(_ mentorID: Cat.ID?, for id: Cat.ID) async {
        guard var current = clan, current.isAlive(id), !isAdvancing else { return }
        MoonEngine.setMentor(mentorID, for: id, in: &current)
        clan = current
        await save()
    }

    func canChooseMate(_ cat: Cat) -> Bool {
        isLivingClanCat(cat) && cat.moons >= 12
    }

    func mateCandidates(for cat: Cat, singleOnly: Bool, kitsOnly: Bool) -> [Cat] {
        clan?.mateCandidates(for: cat.id, singleOnly: singleOnly, kitsOnly: kitsOnly) ?? []
    }

    /// Clangen's romance hearts, 0 to 3, for how one cat feels about another.
    func romanceHearts(from: Cat.ID, to: Cat.ID) -> Int {
        switch clan?.relationship(from: from, to: to)?[.romance] ?? 0 {
        case 81...: 3
        case 31...: 2
        case 10...: 1
        default: 0
        }
    }

    func setMates(_ a: Cat.ID, _ b: Cat.ID) async {
        guard let assets, var current = clan, let relationships = assets.engine.relationships,
              let first = current[a], let second = current[b], current.canChooseMate(first, second), !isAdvancing
        else { return }
        relationships.setMates(a, b, in: &current)
        clan = current
        await save()
    }

    func breakUp(_ a: Cat.ID, _ b: Cat.ID) async {
        guard let assets, let current = clan, current[a]?.mates.contains(b) == true, !isAdvancing else { return }
        isAdvancing = true
        defer { isAdvancing = false }
        clan = await Self.breakUp(a, b, in: current, engine: assets.engine)
        await save()
    }

    func canRename(_ cat: Cat) -> Bool {
        !isOutsider(cat)
    }

    /// The rank ending ("kit", "paw" or "star") a cat's name shows instead of its suffix.
    func specialSuffix(for cat: Cat) -> String? {
        assets?.names.specialSuffix(for: cat.rank)
    }

    /// A fresh name for this cat's looks, for its prefix or suffix.
    func randomName(for cat: Cat) -> CatName? {
        var rng = SystemRandomNumberGenerator()
        return assets?.names.generate(for: cat.appearance, using: &rng)
    }

    /// The name the cat would show after `rename`, cleaned up the same way.
    func previewName(of cat: Cat, prefix: String, suffix: String, hideSpecialSuffix: Bool) -> String {
        guard let assets, var preview = clan else { return displayName(cat) }
        preview.rename(cat.id, prefix: prefix, suffix: suffix, hideSpecialSuffix: hideSpecialSuffix, names: assets.names)
        return preview[cat.id].map(displayName) ?? displayName(cat)
    }

    @discardableResult
    func rename(_ id: Cat.ID, prefix: String, suffix: String, hideSpecialSuffix: Bool) async -> Bool {
        guard let assets, var current = clan, !current.isOutsider(id), !isAdvancing else { return false }
        let changed = current.rename(id, prefix: prefix, suffix: suffix, hideSpecialSuffix: hideSpecialSuffix, names: assets.names)
        clan = current
        await save()
        return changed
    }

    func adoptiveParentCandidates(for cat: Cat, matesOfParentsOnly: Bool, unrelatedOnly: Bool) -> [Cat] {
        clan?.adoptiveParentCandidates(for: cat.id, matesOfParentsOnly: matesOfParentsOnly, unrelatedOnly: unrelatedOnly) ?? []
    }

    func adopt(_ kitID: Cat.ID, by parentID: Cat.ID) async {
        guard var current = clan, !isAdvancing, current.adopt(kitID, by: parentID) else { return }
        clan = current
        await save()
    }

    func unadopt(_ kitID: Cat.ID, from parentID: Cat.ID) async {
        guard var current = clan, !isAdvancing else { return }
        var rng = SystemRandomNumberGenerator()
        guard current.unadopt(kitID, from: parentID, using: &rng) else { return }
        clan = current
        await save()
    }

    /// Sets a Clan cat's gender identity and pronouns, then lets it think anew.
    func setGender(_ id: Cat.ID, genderAlign: GenderAlign, pronouns: Pronouns) async {
        guard let assets, var current = clan, !isAdvancing, current.setGender(id, genderAlign: genderAlign, pronouns: pronouns) else { return }
        var rng = SystemRandomNumberGenerator()
        assets.engine.refreshThought(for: id, in: &current, using: &rng)
        clan = current
        await save()
    }

    /// A sample sentence using these pronouns for the cat.
    func pronounPreview(of cat: Cat, pronouns: Pronouns) -> String {
        guard let assets, let clan else { return "" }
        var cat = cat
        cat.pronouns = pronouns
        let line = "{PRONOUN/m_c/subject/CAP} {VERB/m_c/are/is} proud of {PRONOUN/m_c/self}, and the Clan is proud of {PRONOUN/m_c/object} too."
        return assets.patrols.template.resolve(line, cats: ["m_c": cat], clan: clan)
    }

    /// The cat's current thought, e.g. "Is watching over the kits".
    func thought(of cat: Cat) -> String? {
        guard let clan else { return nil }
        return assets?.thought(of: cat, in: clan)
    }

    func family(of cat: Cat) -> [Kin] {
        clan?.family(of: cat.id) ?? []
    }

    // MARK: - Afterlife

    func showAfterlife() {
        afterlifeTab = clan?.guideAfterlife ?? .starClan
        isShowingAfterlife = true
    }

    func isGuide(_ cat: Cat) -> Bool {
        cat.id == clan?.guide
    }

    /// Whether this is the Clan's living leader.
    func isLeader(_ cat: Cat) -> Bool {
        cat.isAlive && cat.id == clan?.leader
    }

    /// e.g. "past StarClan warrior".
    func pastRank(of cat: Cat) -> String? {
        guard let clan else { return nil }
        return assets?.afterlifeText.pastRank(of: cat, in: clan)
    }

    /// e.g. "dead for 12 moons".
    func deadFor(_ cat: Cat) -> String? {
        assets?.afterlifeText.deadFor(cat)
    }

    func backstory(of cat: Cat) -> String? {
        guard let clan else { return nil }
        return assets?.afterlifeText.backstory(of: cat, in: clan)
    }

    /// How the cat died, one line per death, then how the afterlife received them.
    func deathHistory(of cat: Cat) -> [String] {
        guard let clan, let text = assets?.afterlifeText else { return [] }
        return text.deaths(of: cat, in: clan) + [text.acceptance(of: cat, in: clan)].compactMap(\.self)
    }

    func ceremony(of cat: Cat) -> [String] {
        guard let clan else { return [] }
        return assets?.afterlifeText.ceremony(of: cat, in: clan) ?? []
    }

    func fadedCount(in afterlife: Afterlife) -> Int {
        clan?.faded.count(where: { $0.afterlife == afterlife }) ?? 0
    }

    /// Keeps a dead cat from fading from the afterlife.
    func setPreventFading(_ prevent: Bool, for id: Cat.ID) async {
        guard var current = clan, !isAdvancing else { return }
        if let i = current.index(of: id) {
            current.cats[i].preventFading = prevent
        } else if let i = current.outsiders.firstIndex(where: { $0.id == id }) {
            current.outsiders[i].preventFading = prevent
        } else {
            return
        }
        clan = current
        await save()
    }

    func setFading(_ fading: Bool) async {
        guard clan != nil, !isAdvancing else { return }
        clan?.fading = fading
        await save()
    }

    func setSameSexAdoption(_ on: Bool) async {
        guard clan != nil, !isAdvancing else { return }
        clan?.sameSexAdoption = on
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
        campPlacements = []
        selectedCat = nil
        patrol = nil
        isShowingLeaderDen = false
        isShowingAfterlife = false
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
        clan?.cats.filter { $0.allParents.contains(cat.id) } ?? []
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
        engine.refreshThought(.onExile, for: id, in: &clan, using: &rng)
        return clan
    }

    @concurrent
    private static func changeRank(_ rank: Rank, for id: Cat.ID, in clan: Clan, engine: MoonEngine) async -> (Clan, Bool) {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        let changed = engine.changeRank(rank, for: id, in: &clan, using: &rng)
        if changed { engine.refreshThought(.onRankChange, for: id, in: &clan, using: &rng) }
        return (clan, changed)
    }

    @concurrent
    private static func breakUp(_ a: Cat.ID, _ b: Cat.ID, in clan: Clan, engine: MoonEngine) async -> Clan {
        var clan = clan
        var rng = SystemRandomNumberGenerator()
        engine.relationships?.breakUp(a, b, in: &clan, using: &rng)
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
    /// `-leaderDen clans|outsiders` (opens the leader's den), `-leaderDenPlan YES` (queues a choice for each tab),
    /// `-camp 1…4` (the camp for `-autofound` or the founding flow), `-foundingStep camp`, `-about YES`,
    /// `-deaths N` (sends N living warriors, apprentices or elders to the afterlife),
    /// `-afterlife YES|starclan|dark_forest|unknown_residence` (opens the afterlife), `-afterlifeSort rank|death|name`,
    /// `-adopt YES` (the youngest cat who can be adopted gets its first candidate as an adoptive parent).
    /// The clan screen reads `-clanView camp|list` and `-denLabels YES|NO` straight from its `@AppStorage`.
    func applyDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        guard let assets else { return }

        if defaults.bool(forKey: "autofound") {
            let founding = FoundingModel(assets: assets)
            founding.autopick()
            founding.preyAndHerbs = !defaults.bool(forKey: "classic")
            if let camp = debugCamp { founding.camp = camp }
            await found(from: founding)
        } else if case .founding(let founding) = state {
            switch defaults.string(forKey: "foundingStep") {
            case "cats":
                founding.randomName()
                founding.showCats()
            case "camp":
                founding.autopick()
                founding.showCamp()
            case "options":
                founding.autopick()
                founding.showOptions()
            default:
                break
            }
            if defaults.bool(forKey: "autopick") { founding.autopick() }
            if let camp = debugCamp { founding.camp = camp }
        }

        let moons = defaults.integer(forKey: "timeskips")
        if moons > 0, let current = clan {
            clan = await Self.advance(current, moons: moons, engine: assets.engine)
            latestMoon = clan?.age
            await save()
        }

        await debugOtherClans()
        await debugAfterlife()
        if defaults.bool(forKey: "feed") { await feed(hungryCats.map(\.id)) }
        if defaults.bool(forKey: "adopt"), let clan,
           let kit = clan.living.sorted(by: { $0.moons < $1.moons }).first(where: { !clan.adoptiveParentCandidates(for: $0.id).isEmpty }),
           let parent = clan.adoptiveParentCandidates(for: kit.id).first {
            await adopt(kit.id, by: parent.id)
        }
        selectedCat = debugCatToShow
        isShowingSupplies = defaults.string(forKey: "supplies") != nil
        suppliesStartsAtHerbs = defaults.string(forKey: "supplies") == "herbs"
        isShowingAbout = defaults.bool(forKey: "about")
        rollCamp()
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

    private func debugAfterlife() async {
        let defaults = UserDefaults.standard
        let deaths = defaults.integer(forKey: "deaths")
        if deaths > 0, var current = clan {
            var rng = SystemRandomNumberGenerator()
            let ranks: [Rank] = [.warrior, .apprentice, .elder]
            for cat in current.living.filter({ ranks.contains($0.rank) }).prefix(deaths) {
                current.sendToAfterlife(cat.id, history: "m_c died of a mysterious illness.", using: &rng)
            }
            clan = current
            await save()
        }
        if let tab = defaults.string(forKey: "afterlife") {
            showAfterlife()
            if let afterlife = Afterlife(rawValue: tab) { afterlifeTab = afterlife }
        }
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

    private var debugCamp: Int? {
        let camp = UserDefaults.standard.integer(forKey: "camp")
        return (1...CampLibrary.names.count).contains(camp) ? camp : nil
    }

    /// `-showCat first` opens the leader; `-showCat guide` opens the guide; `-showCat dead` opens the most recently dead Clan cat;
    /// `-showCat outsider` opens the first nearby outsider; `-showCat sick` opens the cat with the most known conditions; `-showCat apprentice` the first apprentice; `-showCat family` the living cat with the most relatives; `-showCat adopted` the first cat with an adoptive parent; any other value opens the first cat whose name starts with it.
    var debugCatToShow: Cat? {
        guard let query = UserDefaults.standard.string(forKey: "showCat"), let clan else { return nil }
        if query == "first" { return clan[clan.leader] ?? clan.living.first }
        if query == "outsider" { return nearbyOutsiders.first }
        if query == "guide" { return clan[clan.guide] }
        if query == "dead" { return clan.dead.last { $0.id != clan.guide } }
        if query == "apprentice" { return clan.living.first { $0.rank.isApprentice } }
        if query == "adopted" { return clan.cats.first { !$0.adoptiveParents.isEmpty } }
        if query == "family" { return clan.living.max { clan.family(of: $0.id).count < clan.family(of: $1.id).count } }
        if query == "sick" {
            return clan.living.max { $0.visibleConditions.count < $1.visibleConditions.count }
        }
        return clan.cats.first { displayName($0).lowercased().hasPrefix(query.lowercased()) }
    }
}
#endif
