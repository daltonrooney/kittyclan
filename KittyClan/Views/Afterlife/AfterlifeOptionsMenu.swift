import SwiftUI

struct AfterlifeOptionsMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var sort: AfterlifeSort

    var body: some View {
        Menu("Sort and options", systemImage: "arrow.up.arrow.down.circle") {
            Picker("Sort by", selection: $sort) {
                ForEach(AfterlifeSort.allCases) { sort in
                    Label(sort.title, systemImage: sort.symbol).tag(sort)
                }
            }
            Divider()
            Toggle("Dead cats fade", systemImage: "aqi.low", isOn: fading)
        }
    }

    private var fading: Binding<Bool> {
        Binding {
            model.clan?.fading ?? true
        } set: { fading in
            Task { await model.setOption(\.fading, fading) }
        }
    }
}
