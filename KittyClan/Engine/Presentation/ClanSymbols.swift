import Foundation

/// A Clan symbol from Clangen's `symbols.png`, e.g. `symbolCRANE1` (the second Crane).
struct ClanSymbol: Codable, Hashable, Identifiable, Sendable {
    let id: String
    /// The Clan prefix it was drawn for, e.g. "Crane".
    let name: String
    let column: Int
    let row: Int
    let tags: [String]

    /// Clangen shows symbols by their sprite name without "symbol", e.g. "CRANE1".
    var label: String { String(id.dropFirst("symbol".count)) }
    /// The broad kind of symbol, e.g. "animal" or "plant".
    var category: String { tags.first ?? "other" }
}

/// Clangen's Clan symbols in its order, with its rules for picking one.
struct ClanSymbols: Sendable {
    static let spriteSize = 50

    let all: [ClanSymbol]
    private let byID: [String: ClanSymbol]

    init(symbols: [ClanSymbol]) {
        all = symbols
        byID = Dictionary(symbols.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    init(url: URL) throws {
        self.init(symbols: try JSONDecoder().decode([ClanSymbol].self, from: Data(contentsOf: url)))
    }

    /// The bundled symbols, or none when the resources are missing.
    static let bundled: ClanSymbols = {
        guard let url = directory?.appending(path: "symbols.json"), let symbols = try? ClanSymbols(url: url) else {
            return ClanSymbols(symbols: [])
        }
        return symbols
    }()

    static var directory: URL? { Bundle.main.url(forResource: "Presentation", withExtension: nil) }

    subscript(id: String) -> ClanSymbol? { byID[id] }

    /// Clangen's `get_symbol` falls back to the first symbol for an unknown name.
    func symbolOrDefault(_ id: String) -> ClanSymbol? { byID[id] ?? all.first }

    /// Broad kinds of symbol in the order they first appear.
    var categories: [String] {
        all.reduce(into: [String]()) { if !$0.contains($1.category) { $0.append($1.category) } }
    }

    /// The symbol Clangen's founding screen picks for a new Clan: the first one drawn for its prefix.
    func recommended(forPrefix prefix: String) -> String? {
        let id = "symbol\(prefix.uppercased())0"
        return byID[id] == nil ? nil : id
    }

    /// Clangen's `clan_symbol_sprite` for a Clan without a symbol: any variant drawn for its prefix, or any symbol.
    func fallback(forPrefix prefix: String, using rng: inout some RandomNumberGenerator) -> String {
        let matching = all.filter { $0.name.uppercased() == prefix.uppercased() }
        return (matching.randomElement(using: &rng) ?? all.randomElement(using: &rng))?.id ?? ""
    }

    func random(using rng: inout some RandomNumberGenerator) -> String {
        all.randomElement(using: &rng)?.id ?? ""
    }
}
