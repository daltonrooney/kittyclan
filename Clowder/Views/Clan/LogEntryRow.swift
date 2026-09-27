import SwiftUI

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(entry.kind.color)
                .frame(width: 22)
                .accessibilityLabel(entry.kind.label)
            Text(entry.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
