import SwiftUI

struct MediationResult: Equatable {
    let title: String
    let lines: [String]
}

struct MediationResultView: View {
    let result: MediationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.title)
                .font(.headline)
            ForEach(Array(result.lines.enumerated()), id: \.offset) { _, line in
                Label(line, systemImage: symbol(for: line))
                    .foregroundStyle(color(for: line))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 16))
    }

    private func symbol(for line: String) -> String {
        if line.hasSuffix("Failed!") { return "xmark.octagon.fill" }
        return line.hasSuffix("increased.") ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    private func color(for line: String) -> Color {
        if line.hasSuffix("Failed!") { return .orange }
        return line.hasSuffix("increased.") ? .green : .red
    }
}
