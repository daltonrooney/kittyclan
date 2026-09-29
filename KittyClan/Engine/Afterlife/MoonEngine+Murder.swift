import Foundation

/// Clangen's murders (`handle_murder`), their history, and the future events that reveal them.
extension MoonEngine {
    /// Clangen's `handle_murder`, rolled for each healthy cat: a rare random murder of someone
    /// the cat dislikes, or a planned one against its worst enemy.
    func handleMurder(by id: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard clan.allowMurder, library != nil, let cat = clan[id], clan.isAlive(id), !cat.rank.isBaby, !cat.isIll, !cat.isInjured else { return [] }
        func bits(_ n: Int) -> UInt64 { UInt64.random(in: 0..<(UInt64(1) << UInt64(min(max(n, 1), 62))), using: &rng) }
        let p = cat.personality
        let feelings = clan.relationships[id] ?? [:]
        func total(_ r: Relationship) -> Int { r.romance + r.like + r.respect + r.comfort + r.trust }

        let randomChance = 25 - 0.5 * Double(p.aggression + (16 - p.stability))
        if bits(Int(randomChance)) == 1 {
            let targets = feelings.filter { clan.isAlive($0.key) && total($0.value) < 0 }.keys.sorted { $0.uuidString < $1.uuidString }
            guard let victim = targets.randomElement(using: &rng) else { return [] }
            return murder(victim, by: id, in: &clan, counts: &counts, using: &rng)
        }

        var capable = 7
        if p.stability < 6 { capable -= 3 }
        if p.lawfulness < 6 { capable -= 2 }
        if p.aggression > 10 { capable -= 1 }
        guard bits(capable) == 1 else { return [] }
        let hated = feelings.filter { key, r in
            clan.isAlive(key) && RelationshipValue.allCases.contains { r[$0] <= -25 }
        }
        guard let (victimID, feeling) = hated.min(by: { total($0.value) < total($1.value) }), let victim = clan[victimID] else { return [] }

        var kill = 80
        for value in RelationshipValue.allCases {
            if feeling[value] <= -70 { kill -= 15 } else if feeling[value] <= -25 { kill -= 5 }
        }
        if ["ambitious", "arrogant", "rebellious"].contains(p.trait), [clan.leader, clan.deputy].contains(victimID) {
            kill -= 10
            if cat.id == clan.deputy { kill -= 15 }
        }
        kill -= p.aggression + (16 - p.stability) + (16 - p.lawfulness)
        kill = max(1, kill)
        if oneIn(kill, &rng) { return murder(victimID, by: id, in: &clan, counts: &counts, using: &rng) }
        guard kill <= 15, let library,
              var pick = library.miscEvent(subTypes: ["failed_murder"], for: cat, fixed: ["r_c": victim.id], in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
              addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) != nil
        else { return [] }
        relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
        applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
        applyEventEffects(pick, in: &clan, using: &rng)
        return [.story(pick, .relationship)]
    }

    /// Kills the victim with a Clangen murder story, records the murder and schedules its reveal.
    func murder(_ victimID: UUID, by murdererID: UUID, in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let victim = clan[victimID], clan.isAlive(victimID), clan.isAlive(murdererID),
              var pick = library?.murderEvent(victim: victim, murderer: murdererID, in: clan, context: eventContext(for: clan, using: &rng), using: &rng),
              pick.deaths.contains(victimID),
              addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) != nil
        else { return [] }

        let record = MurderRecord(murderer: murdererID, victim: victimID, moon: clan.age)
        for id in [murdererID, victimID] {
            if let i = clan.index(of: id) { clan.cats[i].murders.append(record) }
        }
        if let m = clan.index(of: murdererID) {
            clan.cats[m].starClanAffinity -= 40
            clan.cats[m].darkForestAffinity += 20
        }
        schedule(pick, in: &clan, using: &rng)
        return applyDeathEvent(pick, cause: .misfortune, in: &clan, using: &rng)
    }

    /// Queues an event's `future_event`s with the cats they carry over.
    func schedule(_ pick: StoryPick, in clan: inout Clan, using rng: inout some RandomNumberGenerator) {
        for spec in pick.futureEvents {
            let cats = spec.carried.compactMapValues { pick.cats[$0] }
            guard cats["m_c"] != nil else { continue }
            clan.pendingEvents.append(PendingEvent(
                eventType: spec.eventType, subTypes: spec.subTypes,
                moonsLeft: Int.random(in: spec.delay, using: &rng), cats: cats
            ))
        }
    }

    /// Clangen's `trigger_future_events`: waiting events count down, then fire if their cats are
    /// still around, trying for up to twelve more moons.
    func pendingEventsMoon(in clan: inout Clan, counts: inout [UUID: Int], using rng: inout some RandomNumberGenerator) -> [MoonEvent] {
        guard let library else { return [] }
        var events: [MoonEvent] = []
        var waiting: [PendingEvent] = []
        for var pending in clan.pendingEvents {
            pending.moonsLeft -= 1
            guard let mainID = pending.cats["m_c"], clan.isAlive(mainID), pending.cats.values.allSatisfy({ clan[$0] != nil }) else { continue }
            if pending.moonsLeft > 0 {
                waiting.append(pending)
                continue
            }
            if pending.eventType == "death", pending.subTypes.contains("murder"), let murderer = pending.cats["r_c"] {
                let result = murder(mainID, by: murderer, in: &clan, counts: &counts, using: &rng)
                if result.isEmpty, pending.moonsLeft > -12 { waiting.append(pending) }
                events += result
                continue
            }
            guard pending.eventType == "misc", let main = clan[mainID],
                  var pick = library.miscEvent(
                      subTypes: pending.subTypes, for: main, fixed: pending.cats.filter { $0.key != "m_c" },
                      in: clan, context: eventContext(for: clan, using: &rng), using: &rng
                  ),
                  addNewCats(to: &pick, in: &clan, counts: &counts, using: &rng) != nil
            else {
                if pending.moonsLeft > -12 { waiting.append(pending) }
                continue
            }
            relationships?.apply(pick.relationshipChanges, cats: pick.allCats, in: &clan, using: &rng)
            applyInjuries(pick.injuries, cats: pick.cats, in: &clan, using: &rng)
            applyEventEffects(pick, in: &clan, using: &rng)
            if let victim = pending.cats["mur_c"], pending.subTypes.contains(where: { $0.hasSuffix("murder_reveal") }) {
                revealMurder(by: mainID, of: victim, toClan: pick.tags.contains("clan_wide"), to: pick.cats["r_c"], in: &clan)
            }
            schedule(pick, in: &clan, using: &rng)
            events.append(.story(pick, .info))
        }
        clan.pendingEvents = waiting
        return events
    }

    /// Clangen's `reveal_murder`: the whole Clan learns of it, or one more cat does.
    func revealMurder(by murderer: UUID, of victim: UUID, toClan: Bool, to witness: UUID?, in clan: inout Clan) {
        for id in [murderer, victim] {
            guard let i = clan.index(of: id) else { continue }
            for r in clan.cats[i].murders.indices where clan.cats[i].murders[r].murderer == murderer && clan.cats[i].murders[r].victim == victim {
                if toClan { clan.cats[i].murders[r].revealedToClan = true }
                if let witness, !clan.cats[i].murders[r].aware.contains(witness) { clan.cats[i].murders[r].aware.append(witness) }
            }
        }
    }
}
