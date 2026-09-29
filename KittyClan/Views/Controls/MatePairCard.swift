import SwiftUI

/// The cat and the chosen partner side by side, with romance hearts each way and the deciding button.
struct MatePairCard: View {
    @Environment(AppModel.self) private var model
    let cat: Cat
    let partner: Cat?
    let decide: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 20) {
                portrait(cat)
                hearts
                    .frame(minWidth: 120)
                if let partner {
                    portrait(partner)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "questionmark.square.dashed")
                            .font(.system(size: 64))
                            .foregroundStyle(.tertiary)
                            .frame(width: 110, height: 110)
                        Text("Choose a cat")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let partner {
                if partner.sex == cat.sex, model.clan?.sameSexBirth != true {
                    Label(model.clan?.sameSexAdoption == true ? "This pair can adopt kits." : "This pair can't have kits together.", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if cat.mates.contains(partner.id) {
                    Button("Break It Up", systemImage: "heart.slash", role: .destructive, action: decide)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                } else {
                    Button("It's Official!", systemImage: "heart.fill", action: decide)
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                        .controlSize(.large)
                }
            }
        }
        .disabled(model.isAdvancing)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.background, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var hearts: some View {
        if let partner {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    RomanceHearts(count: model.romanceHearts(from: cat.id, to: partner.id), direction: "\(model.displayName(cat)) toward \(model.displayName(partner))")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .foregroundStyle(.secondary)
                    RomanceHearts(count: model.romanceHearts(from: partner.id, to: cat.id), direction: "\(model.displayName(partner)) toward \(model.displayName(cat))")
                }
            }
        } else {
            Image(systemName: "heart")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        }
    }

    private func portrait(_ cat: Cat) -> some View {
        VStack(spacing: 6) {
            CatSprite(cat: cat)
                .frame(width: 110)
            Text(model.displayName(cat))
                .font(.headline)
            Text("\(cat.rank.label), \(cat.moonsText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
