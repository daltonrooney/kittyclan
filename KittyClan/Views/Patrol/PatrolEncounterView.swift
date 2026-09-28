import SwiftUI

struct PatrolEncounterView: View {
    let patrol: PatrolModel
    let session: PatrolSession

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PatrolArt(name: session.introArt)
                    .frame(maxWidth: 320)
                Text(session.intro.storyText)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background, in: .rect(cornerRadius: 16))
                PatrolCatsRow(catIDs: session.cats)
                VStack(spacing: 12) {
                    Button(action: proceed) {
                        Label("Proceed", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brown)
                    if session.canAntagonize {
                        Button(action: antagonize) {
                            Label("Antagonize", systemImage: "flame.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    Button(action: decline) {
                        Label("Do not proceed", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brown)
                }
                .font(.title3.bold())
                .controlSize(.large)
                .frame(maxWidth: 420)
                .disabled(patrol.isWorking)
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }

    private func proceed() { choose(.proceed) }
    private func antagonize() { choose(.antagonize) }
    private func decline() { choose(.decline) }

    private func choose(_ choice: PatrolChoice) {
        Task { await patrol.choose(choice) }
    }
}
