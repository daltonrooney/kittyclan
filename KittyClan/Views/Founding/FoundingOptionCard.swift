import SwiftUI

/// A big, explained on/off choice for the founding options.
struct FoundingOptionCard: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(tint)
                    .frame(width: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.bold())
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(tint)
        .padding(20)
        .background(.background, in: .rect(cornerRadius: 20))
        .opacity(isEnabled ? 1 : 0.55)
    }
}
