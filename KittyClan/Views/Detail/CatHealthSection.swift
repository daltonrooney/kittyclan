import SwiftUI

struct CatHealthSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    /// Clangen's profile notice: expecting or recovering from birth, else just unwell.
    private var note: String? {
        if cat.has("recovering from birth") { return "Recovering from giving birth, so not working or patrolling." }
        if cat.has("pregnant") {
            return cat.isNotWorking ? "Expecting kits, and resting in the nursery." : "Expecting kits, but still well enough to work."
        }
        return cat.isNotWorking ? "Too unwell to work or patrol right now." : nil
    }

    var body: some View {
        let conditions = cat.visibleConditions
        if !conditions.isEmpty {
            Section {
                ForEach(conditions, id: \.self) { condition in
                    ConditionRow(condition: condition, name: model.conditionName(condition), moons: condition.moonsWith(clanAge: model.clan?.age ?? 0))
                }
            } header: {
                Text("Health")
            } footer: {
                if !cat.isDead, let note {
                    Text(note)
                }
            }
        }
    }
}
