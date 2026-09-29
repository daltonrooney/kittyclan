import SwiftUI

struct CatLifeStorySection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    @State private var showsInteractions = false

    var body: some View {
        let story = model.lifeStory(of: cat)
        let hasInteractions = story.contains { $0.entry.kind == .interaction }
        let shown = showsInteractions ? story : story.filter { $0.entry.kind != .interaction }
        Section("Life story") {
            if let backstory = model.profileBackstory(of: cat) {
                Text(backstory)
            }
            if hasInteractions {
                Toggle("Include everyday interactions", isOn: $showsInteractions)
            }
            if shown.isEmpty {
                Text("\(model.displayName(cat))'s story is just beginning.")
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { event in
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
