import Foundation

/// Clangen's `CatThought`: which pool a cat's next thought comes from.
enum ThoughtKind: String, Codable, Sendable, CaseIterable {
    case isGuide = "is_guide", whileDead = "while_dead", whileAlive = "while_alive"
    case onDeath = "on_death", onBirth = "on_birth", onMeeting = "on_meeting", onJoin = "on_join"
    case onExile = "on_exile", onLost = "on_lost", onRankChange = "on_rank_change"
    case onGriefTowardBody = "on_grief_toward_body", onGriefNoBody = "on_grief_no_body"
    case onAfterlifeChange = "on_afterlife_change"
    /// The outside blood parent of an abandoned litter, glad the kits are safe.
    case halfBloodKitting = "half_blood_kitting"
}

/// The one-line thought on a cat's profile: Clangen text with `m_c` for the cat and `r_c` for `about`.
struct Thought: Codable, Hashable, Sendable {
    var text: String
    var about: UUID?
}
