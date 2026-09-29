import SwiftUI

struct TimeskipButton: View {
    @Environment(AppModel.self) private var model
    @Environment(AudioDirector.self) private var audio

    var body: some View {
        Button(action: timeskip) {
            Label("Timeskip", systemImage: "moon.stars.fill")
                .font(.title2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.indigo)
        .disabled(model.isAdvancing)
        .sensoryFeedback(.success, trigger: model.clan?.age)
        .accessibilityHint("Moves the Clan forward one moon")
    }

    private func timeskip() {
        audio.play(.timeskip)
        Task { await model.timeskip() }
    }
}
