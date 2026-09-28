import SwiftUI

struct PatrolSelectionBar: View {
    @Environment(AppModel.self) private var model
    let patrol: PatrolModel

    var body: some View {
        let selected = patrol.selectedCats
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(0..<PatrolModel.maxCats, id: \.self) { slot in
                    if slot < selected.count {
                        Button {
                            patrol.toggle(selected[slot])
                        } label: {
                            CatSprite(cat: selected[slot])
                                .frame(width: 56, height: 56)
                                .background(.background, in: .rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(model.displayName(selected[slot]))")
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.tertiary, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .frame(width: 56, height: 56)
                            .accessibilityHidden(true)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: start) {
                Label("Start patrol", systemImage: "figure.walk")
                    .font(.title3.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.brown)
            .disabled(!patrol.canStart)
        }
        .padding()
        .background(.bar)
    }

    private func start() {
        Task { await patrol.start() }
    }
}
