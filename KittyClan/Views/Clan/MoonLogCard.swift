import SwiftUI

struct MoonLogCard: View {
    let log: MoonLog
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(log.moon == 0 ? "The founding" : "Moon \(log.moon)")
                    .font(.headline)
                Spacer()
                Label(Season(moon: log.moon).rawValue, systemImage: Season(moon: log.moon).symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let events = log.entries.filter { $0.kind != .interaction }
            let interactions = log.entries.filter { $0.kind == .interaction }
            if events.isEmpty {
                Text("A quiet moon passes.")
                    .italic()
                    .foregroundStyle(.secondary)
            }
            ForEach(events) { entry in
                LogEntryRow(entry: entry)
            }
            if !interactions.isEmpty {
                InteractionsDisclosure(entries: interactions)
            }
        }
        .padding()
        .background(isHighlighted ? Color.yellow.opacity(0.25) : Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isHighlighted ? Color.yellow : Color.clear, lineWidth: 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
