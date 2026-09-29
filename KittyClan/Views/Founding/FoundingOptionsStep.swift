import SwiftUI

struct FoundingOptionsStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var founding: FoundingModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("How will your Clan live?")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Prey and herbs can't be changed later, so choose what sounds fun.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 16) {
                    FoundingOptionCard(
                        title: "Prey and herbs",
                        detail: "Your Clan needs food. Send hunting patrols to fill the fresh-kill pile, and medicine cats use herbs to heal.",
                        symbol: "fish.fill",
                        tint: .orange,
                        isOn: $founding.preyAndHerbs
                    )
                    FoundingOptionCard(
                        title: "Cats can starve",
                        detail: founding.preyAndHerbs
                            ? "Hungry cats can die if the Clan runs out of food."
                            : "Turn on prey and herbs to use this.",
                        symbol: "exclamationmark.triangle.fill",
                        tint: .red,
                        isOn: $founding.canStarve
                    )
                    .disabled(!founding.preyAndHerbs)
                    FoundingOptionCard(
                        title: "Warriors and elders may become mediators",
                        detail: "Some cats may choose to settle quarrels instead of fighting or resting. You can change this in Clan Settings.",
                        symbol: "person.2.wave.2.fill",
                        tint: .teal,
                        isOn: $founding.becomeMediator
                    )
                }
                .frame(maxWidth: 560)
            }
            .padding()
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(founding.name)Clan")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: found) {
                Label("Found Clan", systemImage: "flag.fill")
                    .font(.title3.bold())
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(!founding.canFound)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.bar)
        }
        .animation(.snappy, value: founding.preyAndHerbs)
    }

    private func found() {
        Task { await model.found(from: founding) }
    }
}
