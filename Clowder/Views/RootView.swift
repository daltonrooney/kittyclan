import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Gathering the Clan…")
            case .failed(let message):
                LoadFailedView(message: message)
            case .founding(let founding):
                FoundingView(founding: founding)
            case .playing:
                ClanView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        await model.load()
        #if DEBUG
        await model.applyDebugLaunchArguments()
        #endif
    }
}
