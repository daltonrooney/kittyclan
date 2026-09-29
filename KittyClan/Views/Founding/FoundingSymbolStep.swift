import SwiftUI

/// Clangen's Choose Symbol screen: the new Clan's symbol, preselected from its name when one was drawn for it.
struct FoundingSymbolStep: View {
    @Bindable var founding: FoundingModel

    var body: some View {
        ClanSymbolPicker(selection: $founding.symbol, recommended: founding.recommendedSymbol, random: founding.randomSymbol)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Choose a symbol for \(founding.name)Clan")
            .toolbarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button(action: founding.showOptions) {
                        Label("Next", systemImage: "arrow.right")
                            .font(.title3.bold())
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(founding.symbol == nil)
                }
                .controlSize(.extraLarge)
                .padding()
                .background(.bar)
            }
    }
}
