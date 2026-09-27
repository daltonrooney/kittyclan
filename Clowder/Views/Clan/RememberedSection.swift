import SwiftUI

struct RememberedSection: View {
    let cats: [Cat]
    @State private var isExpanded = false

    var body: some View {
        if !cats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: toggle) {
                    HStack {
                        Label("Remembered", systemImage: "sparkles")
                            .font(.title2.bold())
                        Text(cats.count, format: .number)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isHeader)

                if isExpanded {
                    CatGrid(cats: cats.reversed())
                }
            }
            .padding(.top, 8)
        }
    }

    private func toggle() {
        withAnimation(.snappy) { isExpanded.toggle() }
    }
}
