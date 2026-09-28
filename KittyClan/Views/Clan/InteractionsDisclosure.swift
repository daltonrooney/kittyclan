import SwiftUI

/// A moon's everyday interactions, folded into one row so they don't bury the news.
struct InteractionsDisclosure: View {
    let entries: [LogEntry]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: LogEntry.Kind.interaction.symbol)
                        .foregroundStyle(LogEntry.Kind.interaction.color)
                        .frame(width: 22)
                    Text("^[\(entries.count) interaction](inflect: true)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.bold())
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                ForEach(entries) { entry in
                    LogEntryRow(entry: entry)
                        .font(.subheadline)
                }
            }
        }
    }

    private func toggle() {
        withAnimation(.snappy) { isExpanded.toggle() }
    }
}
