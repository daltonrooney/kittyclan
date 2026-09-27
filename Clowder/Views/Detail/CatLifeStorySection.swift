import SwiftUI

struct CatLifeStorySection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    var body: some View {
        Section("Life story") {
            let story = model.lifeStory(of: cat)
            if story.isEmpty {
                Text("\(model.displayName(cat))'s story is just beginning.")
                    .foregroundStyle(.secondary)
            }
            ForEach(story) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.moon == 0 ? "Founding" : "Moon \(event.moon)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    LogEntryRow(entry: event.entry)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
