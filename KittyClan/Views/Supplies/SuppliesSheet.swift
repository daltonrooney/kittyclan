import SwiftUI

struct SuppliesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private static let medicineDen = "medicineDen"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                if let clan = model.clan {
                    if clan.preyAndHerbs {
                        FreshKillSection(pile: clan.freshKill)
                        HungryCatsSection()
                    }
                    MedicineDenSection(supply: clan.herbs, usesHerbs: clan.preyAndHerbs)
                        .id(Self.medicineDen)
                }
            }
            #if DEBUG
            .task {
                if UserDefaults.standard.string(forKey: "supplies") == "herbs" {
                    proxy.scrollTo(Self.medicineDen, anchor: .top)
                }
            }
            #endif
            }
            .navigationTitle("Supplies")
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
