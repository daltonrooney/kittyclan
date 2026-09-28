import SwiftUI

/// Clangen's leader's den: one choice about another Clan and one about an outsider, each moon.
struct LeaderDenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $model.leaderDenTab) {
                        ForEach(LeaderDenTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                switch model.leaderDenTab {
                case .clans: LeaderDenClansView()
                case .outsiders: LeaderDenOutsidersView()
                }
            }
            .navigationTitle("Leader's Den")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
    }
}
