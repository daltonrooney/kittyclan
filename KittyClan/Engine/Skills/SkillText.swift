import Foundation

/// Clangen's skill descriptions from `skills.en.json`, e.g. "fledgeling hunter" or "great healer".
struct SkillText: Sendable {
    private let strings: [String: String]

    init(url: URL) throws {
        strings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    /// One skill as shown on a cat's profile. Apprentices' interests use the ",0.5" wording.
    func describe(_ skill: Skill, adolescent: Bool) -> String {
        let key = adolescent && skill.tier == 0 ? "\(skill.path.rawValue),0.5" : "\(skill.path.rawValue),\(skill.tier)"
        return strings[key] ?? skill.path.shortKey
    }

    /// Clangen's `skill_string`: both skills joined with " & ", or "???" with none.
    func describe(_ cat: Cat) -> String {
        let parts = cat.skills.all.map { describe($0, adolescent: cat.age == .adolescent) }
        return parts.isEmpty ? "???" : parts.joined(separator: " & ")
    }

    /// The short form used in lists, e.g. "hunting & storytelling".
    func short(_ cat: Cat) -> String {
        let parts = cat.skills.all.map { strings[$0.path.shortKey] ?? $0.path.shortKey }
        return parts.isEmpty ? "???" : parts.joined(separator: " & ")
    }
}
