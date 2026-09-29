import SwiftUI

struct ClanMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Clan options", systemImage: "ellipsis.circle") {
            Button("Warriors' Den", systemImage: "scope", action: showFocus)
            Button("Clan Settings", systemImage: "gearshape", action: showSettings)
            Divider()
            Button("Switch Clan…", systemImage: "arrow.left.arrow.right", action: model.showClanChooser)
            Button("Start a New Clan", systemImage: "plus", action: model.startNewClan)
        }
    }

    private func showFocus() {
        model.isShowingFocus = true
    }

    private func showSettings() {
        model.isShowingSettings = true
    }
}
