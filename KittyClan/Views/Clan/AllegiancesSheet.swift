import SwiftUI

/// Clangen's Allegiances: the living Clan by rank, written like the roster at the front of a Warriors book.
struct AllegiancesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            Group {
                if let allegiances = model.allegiances {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            heading(allegiances)
                            ForEach(allegiances.sections) { section in
                                AllegiancesSectionView(section: section, isWide: sizeClass == .regular)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 820, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(item: allegiances.text)
                        }
                    }
                } else {
                    ContentUnavailableView("No Clan", systemImage: "pawprint")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Allegiances")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
    }

    private func heading(_ allegiances: Allegiances) -> some View {
        VStack(spacing: 8) {
            ClanSymbolImage(symbol: model.clan?.symbol)
                .frame(width: 100, height: 100)
            Text("\(allegiances.clanName) Allegiances")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AllegiancesSectionView: View {
    let section: Allegiances.Section
    let isWide: Bool

    var body: some View {
        let layout = isWide ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 20)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        layout {
            Text(section.title)
                .font(.system(.headline, design: .serif, weight: .bold))
                .underline()
                .frame(width: isWide ? 190 : nil, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.entries) { entry in
                    AllegiancesEntryView(entry: entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AllegiancesEntryView: View {
    let entry: Allegiances.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Text(entry.name).fontWeight(.semibold)) - \(entry.description)\(caring)")
                .fixedSize(horizontal: false, vertical: true)
            if let apprentices = entry.apprenticeLine {
                Text(apprentices)
                    .padding(.leading, 32)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(.body, design: .serif))
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    private var caring: Text {
        guard let note = entry.caringFor else { return Text("") }
        return Text(" \(Text(note).italic())")
    }
}
