import SwiftUI

struct LeaderDenOutsidersView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: Cat.ID?

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    var body: some View {
        if let clan = model.clan {
            let outsiders = model.denOutsiders
            let selected = outsiders.first { $0.id == selectedID }
            let canPlan = model.canPlanForOutsiders
            Section {
                DenNoticeRow(text: notice(in: clan), systemImage: canPlan ? "person.fill.questionmark" : "exclamationmark.triangle.fill")
                Label("Outsiders see your Clan as \(clan.reputationStanding).", systemImage: reputationSymbol(clan.reputationStanding))
                if let plan = clan.outsiderDenPlan, let text = model.planText(plan) {
                    DenPlanRow(text: text)
                }
            }
            .onAppear(perform: selectPlanned)

            Section {
                if outsiders.isEmpty {
                    Text("No outsiders are nearby right now.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(outsiders) { cat in
                            OutsiderCell(cat: cat, name: model.displayName(cat), label: model.socialLabel(of: cat), isSelected: cat.id == selectedID) {
                                select(cat.id)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Cats nearby")
            } footer: {
                Text("Tap a cat to decide what to do about them. You can make one choice each moon.")
            }

            if let selected {
                let chosen = chosenAction(for: selected, in: clan)
                Section {
                    ForEach(MoonEngine.outsiderActions(for: selected).compactMap(DenAction.init(rawValue:))) { action in
                        DenActionButton(action: action, isChosen: action == chosen, perform: plan)
                    }
                } header: {
                    Text("What should your Clan do about \(model.displayName(selected))?")
                } footer: {
                    if selected.age == .newborn {
                        Text("\(model.displayName(selected)) is only a newborn. Your Clan can't do anything about them yet.")
                    }
                }
                .disabled(!canPlan || selected.age == .newborn || model.isAdvancing)
            }
        }
    }

    private func notice(in clan: Clan) -> String {
        if clan.living.isEmpty { return "Outsiders do not concern themselves with a dead Clan." }
        guard model.canPlanForOutsiders, let actor = model.leaderDenActor else {
            return "With no one to lead, the Clan can't concern themselves with Outsiders."
        }
        let name = model.displayName(actor)
        if actor.id != clan.leader, let leader = clan[clan.leader] {
            return "\(model.displayName(leader)) and \(name) are discussing what to do about nearby Outsiders."
        }
        return "\(name) is considering what to do about nearby Outsiders."
    }

    private func reputationSymbol(_ standing: String) -> String {
        switch standing {
        case "welcoming": "hand.wave.fill"
        case "hostile": "hand.raised.fill"
        default: "person.fill.questionmark"
        }
    }

    private func chosenAction(for cat: Cat, in clan: Clan) -> DenAction? {
        guard let plan = clan.outsiderDenPlan, plan.target == .outsider(cat.id) else { return nil }
        return DenAction(rawValue: plan.interaction)
    }

    private func selectPlanned() {
        guard selectedID == nil, case .outsider(let id)? = model.clan?.outsiderDenPlan?.target else { return }
        selectedID = id
    }

    private func select(_ id: Cat.ID) {
        withAnimation(.snappy) { selectedID = id }
    }

    private func plan(_ action: DenAction) {
        guard let selectedID else { return }
        Task { await model.planLeaderDen(action, target: .outsider(selectedID)) }
    }
}
