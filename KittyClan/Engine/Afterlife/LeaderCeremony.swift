import Foundation

/// Clangen's nine-lives ceremony text (`lead_ceremony_sc.json` / `lead_ceremony_df.json`).
struct LeaderCeremonyLibrary: Sendable {
    struct Passage: Sendable {
        let tags: [String]
        let leadTraits: [String]
        let texts: [String]
    }

    struct Life: Sendable {
        struct Gift: Sendable {
            let text: String
            let virtues: [String]
        }

        let tags: [String]
        let leadTraits: [String]
        let starTraits: [String]
        let ranks: [String]
        let gifts: [Gift]
    }

    struct Text: Sendable {
        let intros: [Passage]
        let lives: [Life]
        let outros: [Passage]
        let defaultLife: Life.Gift
    }

    let starClan: Text
    let darkForest: Text

    init(directory: URL) throws {
        starClan = try Self.load(directory.appending(path: "afterlife/lead_ceremony_sc.json"))
        darkForest = try Self.load(directory.appending(path: "afterlife/lead_ceremony_df.json"))
    }

    func text(for afterlife: Afterlife) -> Text {
        afterlife == .darkForest ? darkForest : starClan
    }

    private static func load(_ url: URL) throws -> Text {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        func passages(_ key: String) -> [Passage] {
            (json[key] as? [String: [String: Any]] ?? [:]).keys.sorted().compactMap { id in
                guard let entry = (json[key] as? [String: [String: Any]])?[id] else { return nil }
                return Passage(tags: entry["tags"] as? [String] ?? [], leadTraits: entry["lead_trait"] as? [String] ?? [], texts: entry["text"] as? [String] ?? [])
            }
        }
        func gift(_ json: [String: Any]) -> Life.Gift? {
            guard let text = json["text"] as? String else { return nil }
            return Life.Gift(text: text, virtues: json["virtue"] as? [String] ?? [])
        }
        let livesJSON = json["lives"] as? [String: [String: Any]] ?? [:]
        let lives = livesJSON.keys.sorted().compactMap { id -> Life? in
            guard let entry = livesJSON[id] else { return nil }
            return Life(
                tags: entry["tags"] as? [String] ?? [], leadTraits: entry["lead_trait"] as? [String] ?? [],
                starTraits: entry["star_trait"] as? [String] ?? [], ranks: entry["rank"] as? [String] ?? [],
                gifts: (entry["life_giving"] as? [[String: Any]] ?? []).compactMap(gift)
            )
        }
        guard let defaultLife = (json["default_life"] as? [String: Any]).flatMap(gift) else {
            throw SpriteError.missingSheet(url.lastPathComponent)
        }
        return Text(intros: passages("intros"), lives: lives, outros: passages("outros"), defaultLife: defaultLife)
    }
}

extension MoonEngine {
    /// Clangen's `generate_lead_ceremony`: lives from the dead the leader loved most, other cats
    /// of the Clan's afterlife, and one past leader, with an unknown blessing for the rest.
    static func leaderCeremony(for leaderID: UUID, in clan: Clan, library: LeaderCeremonyLibrary, using rng: inout some RandomNumberGenerator) -> [CeremonyLine] {
        guard let leader = clan[leaderID] else { return [] }
        let afterlife = clan.guideAfterlife
        let text = library.text(for: afterlife)
        let lives = clan.leaderLives
        let newClan = clan.age == 0
        let trait = leader.personality.trait

        func fits(tags: [String], leadTraits: [String]) -> Bool {
            if newClan != tags.contains("new_clan") { return false }
            return leadTraits.isEmpty || leadTraits.contains(trait)
        }

        var lines: [CeremonyLine] = []
        if let intro = text.intros.filter({ fits(tags: $0.tags, leadTraits: $0.leadTraits) }).randomElement(using: &rng)?.texts.randomElement(using: &rng) {
            lines.append(CeremonyLine(text: intro))
        }

        let known = (clan.relationships[leaderID] ?? [:]).compactMap { id, relationship -> (Cat, Int)? in
            guard let cat = clan[id], cat.isDead, cat.rank != .newborn, cat.afterlife == afterlife, id != clan.guide else { return nil }
            let total = relationship.romance + relationship.like + relationship.respect + relationship.comfort + relationship.trust
            return (cat, total)
        }
        .sorted { $0.1 > $1.1 }

        var givers: [UUID] = []
        var pastLeader: Cat?
        for (i, (cat, _)) in known.enumerated() {
            if i >= lives - 1 { break }
            if cat.rank == .leader { pastLeader = cat } else { givers.append(cat.id) }
        }

        let inAfterlife = clan.cats.filter { $0.isDead && $0.afterlife == afterlife && !givers.contains($0.id) }
        if givers.count < lives - 1 {
            let needed = lives - 1 - givers.count
            let possible = inAfterlife.filter { ![.leader, .newborn].contains($0.rank) }.shuffled(using: &rng)
            givers += possible.prefix(needed).map(\.id)
        }

        var ancientLeader = false
        if pastLeader == nil {
            let leaders = inAfterlife.filter { $0.rank == .leader }
            if !leaders.isEmpty {
                if Bool.random(using: &rng) {
                    pastLeader = leaders.max { $0.deadFor < $1.deadFor }
                    ancientLeader = true
                } else {
                    pastLeader = leaders.min { $0.deadFor < $1.deadFor }
                }
            }
        }
        if let pastLeader { givers.append(pastLeader.id) }

        let children = Set(clan.children(of: leaderID))
        var usedGifts: Set<String> = []
        var usedVirtues: Set<String> = []
        for giverID in givers {
            guard let giver = clan[giverID] else { continue }
            let options = text.lives.filter { life in
                if life.tags.contains("unknown_blessing") { return false }
                if life.tags.contains("guide"), giverID != clan.guide { return false }
                if newClan != life.tags.contains("new_clan") { return false }
                if life.tags.contains("old_leader"), !ancientLeader { return false }
                if life.tags.contains("leader_parent"), !leader.allParents.contains(giverID) { return false }
                if life.tags.contains("leader_child"), !children.contains(giverID) { return false }
                if !life.ranks.isEmpty, !life.ranks.contains(giver.rank.rawValue) { return false }
                if !life.leadTraits.isEmpty, !life.leadTraits.contains(trait) { return false }
                if !life.starTraits.isEmpty, !life.starTraits.contains(giver.personality.trait) { return false }
                return true
            }
            .flatMap(\.gifts)

            let gift = options.filter { !usedGifts.contains($0.text) }.randomElement(using: &rng)
                ?? options.randomElement(using: &rng) ?? text.defaultLife
            usedGifts.insert(gift.text)
            var virtue: String?
            if !gift.virtues.isEmpty {
                let fresh = gift.virtues.filter { !usedVirtues.contains($0) }
                let chosen = (fresh.isEmpty ? ["faith", "friendship", "love", "strength"] : fresh).randomElement(using: &rng)!
                usedVirtues.insert(chosen)
                virtue = chosen
            }
            lines.append(CeremonyLine(text: gift.text, giver: giverID, virtue: virtue))
        }

        if givers.count < lives,
           let blessing = text.lives.filter({ $0.tags.contains("unknown_blessing") && ($0.leadTraits.isEmpty || $0.leadTraits.contains(trait)) })
               .randomElement(using: &rng)?.gifts.randomElement(using: &rng) {
            lines.append(CeremonyLine(text: blessing.text, extraLives: lives - givers.count))
        }

        if let outro = text.outros.filter({ fits(tags: $0.tags, leadTraits: $0.leadTraits) }).randomElement(using: &rng)?.texts.randomElement(using: &rng) {
            lines.append(CeremonyLine(text: outro, giver: givers.last ?? clan.guide))
        }
        return lines
    }
}
