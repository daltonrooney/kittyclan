import SwiftUI

struct OtherClanRow: View {
    let clan: OtherClan
    let isAtWar: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(clan.name)
                            .font(.title3.bold())
                        StandingChip(standing: clan.standing)
                        if isAtWar {
                            WarBadge()
                        }
                    }
                    Text(clan.temperament.joined(separator: " & ").capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ClanRelationsMeter(clan: clan)
                        .frame(maxWidth: 280)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
