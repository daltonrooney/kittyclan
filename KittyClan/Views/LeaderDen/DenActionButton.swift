import SwiftUI

struct DenActionButton: View {
    let action: DenAction
    let isChosen: Bool
    let perform: (DenAction) -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                Image(systemName: action.systemImage)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundStyle(action.isFriendly ? .green : .red)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.headline)
                    Text(action.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if isChosen {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    private func choose() {
        perform(action)
    }
}
