import SwiftUI

struct PatrolRandomButtons: View {
    let patrol: PatrolModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons
            ScrollView(.horizontal) {
                buttons
            }
            .scrollIndicators(.hidden)
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            Button("Random cat", systemImage: "dice", action: addOne)
                .disabled(patrol.isFull)
            Button("3 random", systemImage: "dice", action: addThree)
                .disabled(patrol.selectedIDs.count > PatrolModel.maxCats - 3)
            Button("6 random", systemImage: "dice", action: addSix)
                .disabled(!patrol.selectedIDs.isEmpty)
            if !patrol.selectedIDs.isEmpty {
                Button("Clear", systemImage: "xmark", role: .destructive, action: patrol.clearSelection)
            }
        }
        .fixedSize()
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
    }

    private func addOne() { patrol.addRandom(1) }
    private func addThree() { patrol.addRandom(3) }
    private func addSix() { patrol.addRandom(6) }
}
