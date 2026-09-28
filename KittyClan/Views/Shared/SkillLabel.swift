import SwiftUI

/// A cat's skills in a compact line, e.g. "hunting & storytelling".
struct SkillLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "star.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.teal)
            .labelStyle(SkillLabelStyle())
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.8)
    }
}

private struct SkillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}
