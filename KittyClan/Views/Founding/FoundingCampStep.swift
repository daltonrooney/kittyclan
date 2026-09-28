import SwiftUI

/// Picks which of Clangen's four forest camps the new Clan settles in.
struct FoundingCampStep: View {
    @Bindable var founding: FoundingModel

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "tent.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.brown)
                        .accessibilityHidden(true)
                    Text("Where will your Clan live?")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Pick a camp for your cats to call home.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(CampLibrary.names.indices, id: \.self) { index in
                        CampPreviewCard(
                            name: CampLibrary.names[index],
                            url: founding.assets.camps.background(camp: index + 1, season: .newleaf, dark: false),
                            isSelected: founding.camp == index + 1,
                            select: { founding.camp = index + 1 }
                        )
                    }
                }
                .frame(maxWidth: 1000)
            }
            .padding()
            .padding(.top, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(founding.name)Clan")
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
            }
            .controlSize(.extraLarge)
            .padding()
            .background(.bar)
        }
    }
}
