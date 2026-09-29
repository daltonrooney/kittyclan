import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AudioDirector.self) private var audio

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Gathering the Clan…")
            case .failed(let message):
                LoadFailedView(message: message)
            case .choosingClan:
                ClanChooserView()
            case .founding(let founding):
                FoundingView(founding: founding)
            case .playing:
                ClanView()
            }
        }
        .task { await load() }
        .onChange(of: model.audioScene, initial: true) { _, scene in
            audio.setScene(scene)
        }
    }

    private func load() async {
        await model.load()
        #if DEBUG
        await model.applyDebugLaunchArguments()
        #endif
    }
}
