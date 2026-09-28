import SwiftUI

/// Clangen's death history: how the cat died, then how the afterlife received them.
struct CatDeathHistorySection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    var body: some View {
        let lines = model.deathHistory(of: cat)
        if !lines.isEmpty {
            Section("History") {
                ForEach(lines.indices, id: \.self) { index in
                    Text(lines[index])
                }
            }
        }
    }
}
