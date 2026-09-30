import SwiftUI

struct PatrolSelectionBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let patrol: PatrolModel

    var body: some View {
        Group {
            if sizeClass == .compact {
                VStack(spacing: 12) {
                    slots
                    startButton
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 12) {
                    slots
                    Spacer(minLength: 0)
                    startButton
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private var slotSize: CGFloat {
        sizeClass == .compact ? 48 : 56
    }

    private var slots: some View {
        let selected = patrol.selectedCats
        return HStack(spacing: sizeClass == .compact ? 6 : 8) {
            ForEach(0..<PatrolModel.maxCats, id: \.self) { slot in
                if slot < selected.count {
                    Button {
                        patrol.toggle(selected[slot])
                    } label: {
                        CatSprite(cat: selected[slot])
                            .frame(width: slotSize, height: slotSize)
                            .background(.background, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(model.displayName(selected[slot]))")
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .frame(width: slotSize, height: slotSize)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var startButton: some View {
        Button(action: start) {
            Label("Start patrol", systemImage: "figure.walk")
                .font(.title3.bold())
                .frame(maxWidth: sizeClass == .compact ? .infinity : nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.brown)
        .disabled(!patrol.canStart)
    }

    private func start() {
        Task { await patrol.start() }
    }
}
