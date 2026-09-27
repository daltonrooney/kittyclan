import SwiftUI

struct CatGridView: View {
    @Bindable var model: ClanModel
    @State private var selected: RenderedCat?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Clowder")
                .toolbar { toolbar }
                .sheet(item: $selected) { rendered in
                    if let assets = model.assets {
                        CatDetailView(cat: rendered.cat, assets: assets, model: model)
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Loading sprites…")
        case .failed(let message):
            ContentUnavailableView("Couldn't load sprites", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.cats) { rendered in
                        Button {
                            selected = rendered
                        } label: {
                            CatCell(rendered: rendered, name: model.displayName(rendered.cat))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await model.generate() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Picker("Age", selection: $model.ageFilter) {
                Text("All ages").tag(CatAge?.none)
                ForEach(CatAge.allCases, id: \.self) { age in
                    Text(age.label).tag(CatAge?.some(age))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: model.ageFilter) {
                Task { await model.generate() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await model.generate() }
            } label: {
                Label("New cats", systemImage: "dice")
            }
            .disabled(model.isGenerating)
        }
    }
}

private struct CatCell: View {
    let rendered: RenderedCat
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            PixelSprite(image: rendered.sprite)
                .padding(8)
                .background(.background, in: .rect(cornerRadius: 12))
            Text(name)
                .font(.headline)
                .lineLimit(1)
            Text("\(rendered.cat.age.label) · \(rendered.cat.moons) moons")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
