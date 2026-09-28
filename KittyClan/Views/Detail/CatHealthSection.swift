import SwiftUI

struct CatHealthSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

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
                if cat.isNotWorking, !cat.isDead {
                    Text("Too unwell to work or patrol right now.")
                }
            }
        }
    }
}
