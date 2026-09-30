import SwiftUI

/// Clangen's mediation screen: a mediator tries to improve, or sabotage, how two cats feel about each other.
struct MediationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let mediator: Cat.ID?

    @State private var mediatorID: Cat.ID?
    @State private var pair: [MediationSlot: Cat.ID] = [:]
    @State private var activeSlot = MediationSlot.first
    @State private var filter = MediationFilter.all
    @State private var allowRomance = false
    @State private var result: MediationResult?

    var body: some View {
        NavigationStack {
            Group {
                if let current = model.cat(mediatorID), current.rank.isMediator, model.isLivingClanCat(current) {
                    content(current)
                } else {
                    ContentUnavailableView("The Clan has no mediators!", systemImage: "person.2.slash",
                                           description: Text("Warriors and elders can become mediators from their profile."))
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mediation")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
        .onAppear(perform: chooseMediator)
    }

    private var randomPairButton: some View {
        Button("Random Pair", systemImage: "dice.fill", action: pickRandom)
            .buttonStyle(.bordered)
    }

    private func mediateButtons(_ block: MediationBlock?) -> some View {
        Group {
            Button { mediate(sabotage: true) } label: {
                Label("Sabotage", systemImage: "hand.thumbsdown.fill")
                    .frame(maxWidth: sizeClass == .compact ? .infinity : nil)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Button { mediate(sabotage: false) } label: {
                Label("Improve", systemImage: "hand.thumbsup.fill")
                    .frame(maxWidth: sizeClass == .compact ? .infinity : nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)
        }
        .disabled(block != nil)
    }

    private func content(_ mediator: Cat) -> some View {
        let first = model.cat(pair[.first])
        let second = model.cat(pair[.second])
        let block = model.mediationBlock(mediator.id, first?.id, second?.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if model.mediators.count > 1 {
                    Picker("Mediator", selection: $mediatorID) {
                        ForEach(model.mediators) { cat in
                            Text(model.displayName(cat)).tag(Optional(cat.id))
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: mediatorID) { removeMediatorFromPair() }
                }
                MediatorCard(mediator: mediator, status: status(block, mediator: mediator), isBlocked: block != nil && block != .invalidPair)

                HStack(spacing: 12) {
                    slotCard(.first, cat: first)
                    slotCard(.second, cat: second)
                }

                if let first, let second {
                    VStack(spacing: 12) {
                        MediationFeelingsView(from: first, to: second)
                        MediationFeelingsView(from: second, to: first)
                        if model.canMediateRomance(first, second) {
                            Toggle("Allow romance", systemImage: "heart", isOn: $allowRomance)
                                .tint(.pink)
                        }
                    }
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 16))
                }

                Group {
                    if sizeClass == .compact {
                        VStack(alignment: .leading, spacing: 12) {
                            randomPairButton
                            HStack(spacing: 12) {
                                mediateButtons(block)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            randomPairButton
                            Spacer()
                            mediateButtons(block)
                        }
                    }
                }
                .disabled(model.isAdvancing)
                .controlSize(.large)

                if let result {
                    MediationResultView(result: result)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Choose the \(activeSlot.title.lowercased())")
                            .font(.headline)
                        Spacer()
                        Picker("Filter", selection: $filter) {
                            ForEach(MediationFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        .disabled(model.cat(pair[activeSlot.other]) == nil)
                    }
                    CatPickerGrid(cats: candidates(for: activeSlot, mediator: mediator), emptyText: "No cats match.") { cat in
                        CatPickerCell(cat: cat, caption: cat.rank.label, tag: tag(for: cat), isSelected: pair[activeSlot] == cat.id) {
                            choose(cat.id)
                        }
                    }
                }
            }
            .padding()
        }
        #if DEBUG
        .onAppear(perform: applyDebugArguments)
        #endif
    }

    private func slotCard(_ slot: MediationSlot, cat: Cat?) -> some View {
        MediationSlotCard(slot: slot, cat: cat, isActive: activeSlot == slot) {
            activeSlot = slot
        } clear: {
            pair[slot] = nil
            activeSlot = slot
            allowRomance = false
        }
    }

    private func status(_ block: MediationBlock?, mediator: Cat) -> String {
        let name = model.displayName(mediator)
        return switch block {
        case .cantWork: "\(name) can't work this moon."
        case .alreadyWorked: "\(name) has already worked this moon."
        case .pairAlreadyMediated: "This pair has already been mediated this moon."
        case .invalidPair: "Choose two cats for \(name) to mediate between."
        case .notMediator: "\(name) isn't a mediator."
        case nil: "\(name) is ready to mediate."
        }
    }

    private func tag(for cat: Cat) -> String? {
        if pair[.first] == cat.id { return MediationSlot.first.title }
        if pair[.second] == cat.id { return MediationSlot.second.title }
        return nil
    }

    /// Living Clan cats other than the mediator, filtered by how the other chosen cat feels about them.
    private func candidates(for slot: MediationSlot, mediator: Cat) -> [Cat] {
        guard let clan = model.clan else { return [] }
        let other = pair[slot.other]
        return clan.living.filter { cat in
            guard cat.id != mediator.id, cat.id != other else { return false }
            guard let other else { return true }
            return filter.includes(clan.relationship(from: other, to: cat.id))
        }
    }

    private func chooseMediator() {
        guard mediatorID == nil else { return }
        let mediators = model.mediators
        mediatorID = mediator.flatMap { id in mediators.first { $0.id == id }?.id }
            ?? mediators.first { model.mediationBlock($0.id, nil, nil) == .invalidPair }?.id
            ?? mediators.first?.id
    }

    private func removeMediatorFromPair() {
        for slot in MediationSlot.allCases where pair[slot] == mediatorID { pair[slot] = nil }
        result = nil
    }

    private func choose(_ id: Cat.ID) {
        pair[activeSlot] = pair[activeSlot] == id ? nil : id
        if pair[activeSlot] != nil, pair[activeSlot.other] == nil { activeSlot = activeSlot.other }
        allowRomance = false
        result = nil
    }

    private func pickRandom() {
        guard let mediator = model.cat(mediatorID) else { return }
        let firsts = candidates(for: .first, mediator: mediator).filter { $0.id != pair[.second] }
        pair = [:]
        guard let first = firsts.randomElement() else { return }
        pair[.first] = first.id
        pair[.second] = candidates(for: .second, mediator: mediator).randomElement()?.id
        activeSlot = pair[.second] == nil ? .second : .first
        allowRomance = false
        result = nil
    }

    private func mediate(sabotage: Bool) {
        guard let mediatorID, let a = pair[.first], let b = pair[.second] else { return }
        let romance = allowRomance
        Task {
            guard let lines = await model.mediate(mediatorID, a, b, sabotage: sabotage, allowRomance: romance) else { return }
            let names: [String] = [mediatorID, a, b].map { id in model.cat(id).map(model.displayName) ?? "" }
            let verb = sabotage ? "meddled with" : "mediated between"
            result = MediationResult(title: "\(names[0]) \(verb) \(names[1]) and \(names[2]).", lines: lines)
        }
    }

    #if DEBUG
    @MainActor private static var didApplyDebugArguments = false

    /// `-mediatePick YES` chooses a random pair; `-mediateRun improve|sabotage` then mediates once.
    private func applyDebugArguments() {
        let defaults = UserDefaults.standard
        guard !Self.didApplyDebugArguments else { return }
        Self.didApplyDebugArguments = true
        if defaults.bool(forKey: "mediatePick") { pickRandom() }
        if let run = defaults.string(forKey: "mediateRun") { mediate(sabotage: run == "sabotage") }
    }
    #endif
}
