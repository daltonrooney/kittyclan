import SwiftUI

struct MoonLogPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach((model.clan?.history ?? []).reversed()) { log in
                        MoonLogCard(log: log, isHighlighted: log.moon == model.latestMoon)
                            .id(log.moon)
                    }
                }
                .padding()
            }
            .onChange(of: model.clan?.age) { _, age in
                withAnimation { proxy.scrollTo(age, anchor: .top) }
            }
        }
        .task(id: model.latestMoon) { await clearHighlight() }
    }

    private func clearHighlight() async {
        guard model.latestMoon != nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.8)) { model.clearHighlight() }
    }
}
