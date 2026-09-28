import SwiftUI

/// The choice waiting for next moon, in Clangen's words.
struct DenPlanRow: View {
    let text: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.headline)
                Text("You'll find out how it went next moon. Choosing again changes the plan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "crown.fill")
                .foregroundStyle(.yellow)
        }
    }
}
