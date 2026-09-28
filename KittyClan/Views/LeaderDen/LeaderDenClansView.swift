import SwiftUI

struct LeaderDenClansView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: OtherClan.ID?

    var body: some View {
        if let clan = model.clan {
            let actor = model.leaderDenActor
            let selected = clan.otherClan(selectedID)
            Section {
                DenNoticeRow(text: notice(in: clan, actor: actor), systemImage: actor == nil ? "exclamationmark.triangle.fill" : "person.2.wave.2.fill")
                Label("The other Clans think \(clan.displayName) is \(model.clanTemperament).", systemImage: "eye.fill")
                if let plan = clan.leaderDenPlan, let text = model.planText(plan) {
                    DenPlanRow(text: text)
                }
            }
            .onAppear(perform: selectPlanned)

            Section {
                ForEach(clan.otherClans) { other in
                    OtherClanRow(clan: other, isAtWar: clan.war.enemy == other.id, isSelected: other.id == selectedID) {
                        select(other.id)
                    }
                }
            } header: {
                Text("Neighbouring Clans")
            } footer: {
                Text("Tap a Clan to choose what to do at the next Gathering. You can make one choice each moon.")
            }

            if let selected {
                let (unfriendly, friendly) = MoonEngine.leaderDenActions(for: selected.standing)
                let chosen = chosenAction(for: selected, in: clan)
                Section("What should your Clan do about \(selected.name)?") {
                    ForEach([friendly, unfriendly].compactMap(DenAction.init(rawValue:))) { action in
                        DenActionButton(action: action, isChosen: action == chosen, perform: plan)
                    }
                }
                .disabled(actor == nil || model.isAdvancing)
            }
        }
    }

    private func notice(in clan: Clan, actor: Cat?) -> String {
        guard let actor else {
            return clan.living.isEmpty
                ? "No one is left to attend a Gathering."
                : "With no one to lead, the Clan can't focus on what to say at the Gathering."
        }
        let name = model.displayName(actor)
        if actor.id != clan.leader, let leader = clan[clan.leader], clan.isAlive(leader.id) {
            return "\(model.displayName(leader)) and \(name) are discussing how to handle the next Gathering."
        }
        return "\(name) is considering how to handle the next Gathering."
    }

    private func chosenAction(for other: OtherClan, in clan: Clan) -> DenAction? {
        guard let plan = clan.leaderDenPlan, plan.target == .clan(other.id) else { return nil }
        return DenAction(rawValue: plan.interaction)
    }

    private func selectPlanned() {
        guard selectedID == nil, case .clan(let id)? = model.clan?.leaderDenPlan?.target else { return }
        selectedID = id
    }

    private func select(_ id: OtherClan.ID) {
        withAnimation(.snappy) { selectedID = id }
    }

    private func plan(_ action: DenAction) {
        guard let selectedID else { return }
        Task { await model.planLeaderDen(action, target: .clan(selectedID)) }
    }
}
