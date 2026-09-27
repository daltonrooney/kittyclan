import SwiftUI

struct CandidateCell: View {
    let cat: Cat
    let name: String
    let role: ClanFounding.Role?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                CatSprite(cat: cat)
                    .padding(8)
                    .background(.background, in: .rect(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if let role {
                            RoleBadge(role: role)
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(cat.rank.label) · \(cat.moonsText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(role == nil ? Color.clear : Color.accentColor.opacity(0.15), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(role == nil ? Color.clear : Color.accentColor, lineWidth: 3)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(cat.rank.label), \(cat.moonsText)")
        .accessibilityValue(role?.title ?? "Not chosen")
        .accessibilityAddTraits(.isButton)
    }
}
