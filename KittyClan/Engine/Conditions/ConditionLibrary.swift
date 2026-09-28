import Foundation

/// One entry from Clangen's `injuries.json`, `illnesses.json` or `permanent_conditions.json`.
struct ConditionInfo: Sendable {
    let kind: ConditionKind
    let severity: String
    let duration: Int
    let medicineDuration: Int
    let mortality: [String: Int]
    let medicineMortality: [String: Int]
    let risks: [ConditionRisk]
    let alsoGot: [String]
    let causePermanent: [String]
    let infectiousness: Int
    let congenital: String
    let moonsUntil: Int
    /// Herbs that treat it, by strength (1–3).
    let herbs: [Int: [String]]
    var hasHerbs: Bool { herbs.values.contains { !$0.isEmpty } }

    init(kind: ConditionKind, _ json: [String: Any]) {
        self.kind = kind
        severity = json["severity"] as? String ?? "minor"
        duration = json["duration"] as? Int ?? 0
        medicineDuration = json["medicine_duration"] as? Int ?? duration
        mortality = json["mortality"] as? [String: Int] ?? [:]
        medicineMortality = json["medicine_mortality"] as? [String: Int] ?? mortality
        risks = (json["risks"] as? [[String: Any]] ?? []).compactMap { r in
            (r["name"] as? String).map { ConditionRisk(name: $0, chance: r["chance"] as? Int ?? 0) }
        }
        alsoGot = json["also_got"] as? [String] ?? []
        causePermanent = json["cause_permanent"] as? [String] ?? []
        infectiousness = json["infectiousness"] as? Int ?? 0
        congenital = json["congenital"] as? String ?? "never"
        moonsUntil = json["moons_until"] as? Int ?? 0
        let herbs = json["herbs"] as? [String: [String]] ?? [:]
        self.herbs = Dictionary(uniqueKeysWithValues: herbs.compactMap { key, value in Int(key).map { ($0, value) } })
    }
}

/// Clangen's condition data, text and the constant tables its condition code uses.
struct ConditionLibrary: @unchecked Sendable {
    let conditions: [String: ConditionInfo]
    let seasons: [String: [String: Int]]
    let displayNames: [String: String]
    /// e.g. `strings["gain_illness_strings"]["running nose"]`.
    private let text: [String: [String: Any]]

    init(directory: URL) throws {
        func load(_ name: String) throws -> Any {
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "conditions/\(name).json")))
        }
        var conditions: [String: ConditionInfo] = [:]
        for (file, kind) in [("injuries", ConditionKind.injury), ("illnesses", .illness), ("permanent_conditions", .permanent)] {
            for (name, value) in try load(file) as? [String: Any] ?? [:] {
                if let json = value as? [String: Any] { conditions[name] = ConditionInfo(kind: kind, json) }
            }
        }
        self.conditions = conditions
        seasons = try load("illnesses_seasons") as? [String: [String: Int]] ?? [:]
        var names: [String: String] = [:]
        for file in ["injuries.en", "illnesses.en", "permanent_conditions.en"] {
            names.merge(try load(file) as? [String: String] ?? [:]) { a, _ in a }
        }
        displayNames = names
        var text: [String: [String: Any]] = [:]
        for file in [
            "gain_illness_strings", "gain_permanent_condition_strings", "gain_congenital_condition_strings",
            "illness_healed_strings", "illness_death_strings", "injury_healed_strings", "injury_death_strings",
            "illness_risk_strings", "injuries_risk_strings", "permanent_condition_risk_strings",
        ] {
            text[file] = try load(file) as? [String: Any] ?? [:]
        }
        self.text = text
    }

    func displayName(_ name: String) -> String { displayNames[name] ?? name }

    func strings(_ file: String, _ key: String) -> [String] {
        // Clangen's fleas entry is keyed "fleas:".
        (text[file]?[key] ?? text[file]?[key + ":"]) as? [String] ?? []
    }

    func strings(_ file: String, _ key: String, _ inner: String) -> [String] {
        (text[file]?[key] as? [String: Any])?[inner] as? [String] ?? []
    }

    // MARK: - Constant tables from Clangen's condition code

    static let injuryGroups: [String: [String]] = [
        "battle_injury": ["claw-wound", "mangled leg", "mangled tail", "torn pelt", "cat bite"],
        "minor_injury": ["sprain", "sore", "bruises", "scrapes"],
        "blunt_force_injury": ["broken bone", "broken back", "head damage", "broken jaw"],
        "hot_injury": ["heat exhaustion", "heat stroke", "dehydrated"],
        "cold_injury": ["shivering", "frostbite"],
        "big_bite_injury": ["bite-wound", "broken bone", "torn pelt", "mangled leg", "mangled tail"],
        "small_bite_injury": ["bite-wound", "torn ear", "torn pelt", "scrapes"],
        "beak_bite": ["beak bite", "torn ear", "scrapes"],
        "rat_bite": ["rat bite", "torn ear", "torn pelt"],
        "sickness": ["greencough", "redcough", "whitecough", "yellowcough"],
    ]

    static let scarAllowed: [String: [String]] = [
        "bite-wound": ["LEGBITE", "NECKBITE", "TAILSCAR", "BRIGHTHEART"],
        "cat bite": ["CATBITE", "CATBITETWO"],
        "severe burn": ["BRIGHTHEART", "BURNPAWS", "BURNTAIL", "BURNBELLY", "BURNRUMP"],
        "rat bite": ["RATBITE", "TOE"],
        "snake bite": ["SNAKE", "SNAKETWO"],
        "mangled tail": ["TAILSCAR", "TAILBASE", "NOTAIL", "HALFTAIL", "MANTAIL"],
        "mangled leg": ["NOPAW", "TOETRAP", "MANLEG", "FOUR"],
        "torn ear": ["LEFTEAR", "RIGHTEAR", "NOLEFTEAR", "NORIGHTEAR"],
        "frostbite": ["HALFTAIL", "NOTAIL", "NOPAW", "NOLEFTEAR", "NORIGHTEAR", "NOEAR", "FROSTFACE", "FROSTTAIL", "FROSTMITT", "FROSTSOCK"],
        "damaged eyes": ["THREE", "RIGHTBLIND", "LEFTBLIND", "BOTHBLIND"],
        "quilled by a porcupine": ["QUILLCHUNK", "QUILLSCRATCH", "QUILLSIDE"],
        "claw-wound": ["ONE", "TWO", "SNOUT", "TAILSCAR", "CHEEK", "SIDE", "THROAT", "TAILBASE", "BELLY", "FACE", "BRIDGE", "HINDLEG", "BACK", "SCRATCHSIDE"],
        "beak bite": ["BEAKCHEEK", "BEAKLOWER", "BEAKSIDE"],
        "broken jaw": ["SNOUT", "CHEEK", "BRIDGE", "BEAKCHEEK"],
        "broken back": ["TWO", "TAILBASE", "BACK"],
        "broken bone": ["MANLEG", "TOETRAP", "FOUR"],
    ]

    static let scarToCondition: [String: [String]] = [
        "THREE": ["one bad eye", "failing eyesight"], "FOUR": ["weak leg"],
        "LEFTEAR": ["partial hearing loss"], "RIGHTEAR": ["partial hearing loss"],
        "NOLEFTEAR": ["partial hearing loss"], "NORIGHTEAR": ["partial hearing loss"],
        "NOEAR": ["partial hearing loss", "deaf"], "NOPAW": ["lost a leg"],
        "NOTAIL": ["lost their tail"], "HALFTAIL": ["lost their tail"], "BRIGHTHEART": ["one bad eye"],
        "LEFTBLIND": ["one bad eye", "failing eyesight"], "RIGHTBLIND": ["one bad eye", "failing eyesight"],
        "BOTHBLIND": ["failing eyesight", "blind"], "MANLEG": ["weak leg", "twisted leg"],
        "RATBITE": ["weak leg"], "LEGBITE": ["weak leg"], "TOETRAP": ["weak leg"], "HINDLEG": ["weak leg"],
        "THROAT": ["damaged throat"],
    ]

    static let scarlessConditions: Set<String> = [
        "weak leg", "paralyzed", "raspy lungs", "wasting disease", "blind", "failing eyesight", "one bad eye",
        "partial hearing loss", "deaf", "constant joint pain", "constantly dizzy", "recurring shock", "lasting grief",
        "persistent headaches", "selective mutism", "absent", "crooked jaw",
    ]

    /// Scars that disable a cat, which healing leaves out two times in three.
    static let conditionScars: Set<String> = [
        "LEGBITE", "THREE", "NOPAW", "TOETRAP", "NOTAIL", "HALFTAIL", "LEFTEAR", "RIGHTEAR", "MANLEG", "BRIGHTHEART",
        "NOLEFTEAR", "NORIGHTEAR", "NOEAR", "LEFTBLIND", "RIGHTBLIND", "BOTHBLIND", "RATBITE",
    ]

    /// Conditions that turn into the next stage rather than being added alongside.
    static let illnessProgression: [String: String] = [
        "running nose": "whitecough", "kittencough": "whitecough", "whitecough": "greencough",
        "greencough": "yellowcough", "yellowcough": "redcough", "an infected wound": "a festering wound",
        "heat exhaustion": "heat stroke", "stomachache": "diarrhea", "grief stricken": "lasting grief",
    ]
    static let injuryProgression: [String: String] = ["poisoned": "redcough", "shock": "lingering shock"]
    static let permanentProgression: [String: String] = [
        "one bad eye": "failing eyesight", "failing eyesight": "blind", "partial hearing loss": "deaf",
    ]

    /// Traits that make a cat more likely to get hurt.
    static let riskyTraits: Set<String> = [
        "adventurous", "bold", "daring", "confident", "ambitious", "bloodthirsty", "fierce", "strict",
        "troublesome", "vengeful", "impulsive",
    ]

    /// 1-in-N odds that a disability makes an apprentice or warrior retire, by severity and age.
    static let retirementOdds: [String: [CatAge: Int]] = [
        "severe": [.adolescent: 50, .youngAdult: 10, .adult: 5, .seniorAdult: 5, .senior: 5],
        "major": [.adolescent: 100, .youngAdult: 80, .adult: 70, .seniorAdult: 50, .senior: 10],
    ]
}
