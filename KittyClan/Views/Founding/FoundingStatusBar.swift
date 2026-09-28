import SwiftUI

struct FoundingStatusBar: View {
    let founding: FoundingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(prompt)
                    .font(.title2.bold())
                Spacer()
                Text("\(founding.selectedCount) of \(ClanFounding.memberRange.lowerBound)–\(ClanFounding.memberRange.upperBound) cats")
                    .font(.headline)
                    .monospacedDigit()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(counterColor.opacity(0.2), in: .capsule)
                    .foregroundStyle(counterColor)
            }
            if let leader = founding.leader {
                Label("Led by \(founding.displayName(of: leader))", systemImage: "crown.fill")
                    .foregroundStyle(.orange)
                    .font(.headline)
            }
            if let notice = founding.notice {
                Label(notice, systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    private var prompt: String {
        if founding.canFound && founding.isFull { return "Your Clan is ready!" }
        return switch founding.selection.nextRole {
        case .leader: "Tap a cat to be your leader"
        case .deputy: "Now choose a deputy"
        case .medicineCat: "Now choose a medicine cat"
        case .member where founding.canFound: "Add more cats, or found your Clan"
        case .member: "Choose more cats to join"
        }
    }

    private var counterColor: Color {
        ClanFounding.memberRange.contains(founding.selectedCount) ? .green : .secondary
    }
}
