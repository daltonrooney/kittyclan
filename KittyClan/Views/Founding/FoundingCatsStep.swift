import SwiftUI

struct FoundingCatsStep: View {
    @Environment(AppModel.self) private var model
    let founding: FoundingModel

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FoundingStatusBar(founding: founding)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(founding.candidates) { cat in
                        CandidateCell(
                            cat: cat,
                            name: founding.displayName(of: cat),
                            role: founding.role(of: cat),
                            skills: model.assets?.skillText.short(cat)
                        ) {
                            founding.toggle(cat)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(founding.name)Clan")
        .toolbarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Button(action: founding.reroll) {
                    Label("Reroll (\(founding.rerollsLeft) left)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.title3.bold())
                }
                .buttonStyle(.bordered)
                .disabled(founding.rerollsLeft == 0)
                Spacer()
                Button(action: founding.showOptions) {
                    Label("Next", systemImage: "arrow.right")
                        .font(.title3.bold())
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!founding.canFound)
            }
            .controlSize(.extraLarge)
            .padding()
            .background(.bar)
        }
        .animation(.snappy, value: founding.selectedCount)
    }
}
