import SwiftUI

/// Picks the kind of land the new Clan lives in, as Clangen's biome buttons do.
struct FoundingBiomeStep: View {
    @Bindable var founding: FoundingModel

    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text("What land will your Clan call home?")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("Each territory has its own camps, prey and dangers.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(Biome.allCases, id: \.self) { biome in
                        BiomeCard(
                            biome: biome,
                            urls: (1...biome.campNames.count).map {
                                founding.assets.camps.background(biome: biome, camp: $0, season: .newleaf, dark: false)
                            },
                            isSelected: founding.biome == biome,
                            select: { founding.biome = biome }
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
            HStack(spacing: 16) {
                Button(action: founding.surpriseMe) {
                    Label("Surprise me", systemImage: "dice.fill")
                        .font(.title3.bold())
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(action: founding.showCamp) {
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

/// One biome: a mosaic of its four camps in Newleaf, its name and what it's like.
private struct BiomeCard: View {
    let biome: Biome
    let urls: [URL]
    let isSelected: Bool
    let select: () -> Void

    @State private var images: [CGImage?] = []

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                    GridRow { tile(0); tile(1) }
                    GridRow { tile(2); tile(3) }
                }
                .clipShape(.rect(cornerRadius: 14))
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .tint)
                            .padding(10)
                    }
                }
                Label(biome.displayName, systemImage: biome.symbol)
                    .font(.title2.bold())
                Text(biome.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.background, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(biome.displayName). \(biome.blurb)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .task(id: urls) {
            var loaded: [CGImage?] = []
            for url in urls { loaded.append(await CampBackdrop.loadImage(url)) }
            images = loaded
        }
    }

    private func tile(_ index: Int) -> some View {
        Group {
            if let image = images.indices.contains(index) ? images[index] : nil {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .aspectRatio(CampLayout.canvas.width / CampLayout.canvas.height, contentMode: .fit)
    }
}
