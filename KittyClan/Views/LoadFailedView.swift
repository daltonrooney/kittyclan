import SwiftUI

struct LoadFailedView: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't open your Clan", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if model.assets != nil {
                Button("Start a new Clan", action: model.startNewClan)
            }
        }
    }
}
