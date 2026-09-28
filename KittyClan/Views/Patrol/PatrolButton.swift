import SwiftUI

struct PatrolButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let available = model.patrolEligible.count
        Button(action: model.beginPatrol) {
            HStack(spacing: 8) {
                Label("Patrol", systemImage: "figure.walk")
                    .font(.title2.bold())
                Text(available, format: .number)
                    .font(.headline.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.25), in: .capsule)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.brown)
        .disabled(available == 0 || model.isAdvancing)
        .accessibilityValue("^[\(available) cat](inflect: true) can patrol this moon")
        .accessibilityHint("Sends cats out on patrol")
    }
}
