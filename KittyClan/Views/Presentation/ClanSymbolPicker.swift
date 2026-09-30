import SwiftUI

/// Clangen's symbol chooser: the chosen symbol large, the one drawn for the Clan's name,
/// and every symbol in a grid that can be searched and filtered by kind.
struct ClanSymbolPicker: View {
    @Environment(AudioDirector.self) private var audio
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var selection: String?
    let recommended: String?
    let random: () -> Void

    @State private var search = ""
    @State private var category: String?

    private let catalog = ClanSymbols.bundled
    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 12)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    chosen
                    filters
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(shown) { symbol in
                            cell(symbol)
                                .id(symbol.id)
                        }
                    }
                    .frame(maxWidth: 1000)
                    if shown.isEmpty {
                        ContentUnavailableView.search(text: search)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                if let selection { proxy.scrollTo(selection, anchor: .center) }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search symbols")
    }

    private var chosen: some View {
        HStack(spacing: sizeClass == .compact ? 16 : 24) {
            ClanSymbolImage(symbol: selection)
                .frame(width: sizeClass == .compact ? 88 : 128, height: sizeClass == .compact ? 88 : 128)
                .padding(12)
                .background(.fill.tertiary, in: .rect(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 8) {
                Text(selection.flatMap { catalog[$0]?.label } ?? "No symbol chosen")
                    .font(.title.bold())
                    .monospaced()
                Text("Recommended: \(recommended.flatMap { catalog[$0]?.label } ?? "none for this name")")
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { symbolButtons }
                    VStack(alignment: .leading) { symbolButtons }
                }
                .buttonStyle(.bordered)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 1000)
    }

    @ViewBuilder
    private var symbolButtons: some View {
        if let recommended, recommended != selection {
            Button("Use recommended", systemImage: "star") { selection = recommended }
                .fixedSize()
        }
        Button("Random symbol", systemImage: "dice.fill") {
            audio.play(.diceRoll)
            random()
        }
        .fixedSize()
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack {
                filterChip("All", value: nil)
                ForEach(catalog.categories, id: \.self) { filterChip($0.capitalized, value: $0) }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 1000)
    }

    private func filterChip(_ title: String, value: String?) -> some View {
        Button(title) { category = value }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(category == value ? .accentColor : .secondary)
    }

    private var shown: [ClanSymbol] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return catalog.all.filter { symbol in
            (category == nil || symbol.category == category)
                && (query.isEmpty || symbol.name.localizedStandardContains(query) || symbol.tags.contains { $0.localizedStandardContains(query) })
        }
    }

    private func cell(_ symbol: ClanSymbol) -> some View {
        let isSelected = symbol.id == selection
        return Button {
            selection = symbol.id
        } label: {
            VStack(spacing: 4) {
                ClanSymbolImage(symbol: symbol.id)
                    .frame(width: 50, height: 50)
                Text(symbol.label)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(.tint, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
