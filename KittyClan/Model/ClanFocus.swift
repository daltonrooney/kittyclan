import Foundation

/// Clangen's warriors' den focus: what the Clan's warriors spend each moon on.
enum ClanFocus: String, Codable, CaseIterable, Sendable {
    case businessAsUsual = "business_as_usual"
    case hunting
    case herbGathering = "herb_gathering"
    case threatenOutsiders = "threaten_outsiders"
    case seekOutsiders = "seek_outsiders"
    case restAndRecover = "rest_and_recover"
    case sabotageOtherClans = "sabotage_other_clans"
    case aidOtherClans = "aid_other_clans"
    case raidOtherClans = "raid_other_clans"
    case hoarding

    /// Moons between focus changes.
    static let duration = 3

    var title: String {
        switch self {
        case .businessAsUsual: "Business as Usual"
        case .hunting: "Feeding the Clan"
        case .herbGathering: "Assisting with Herb Gathering"
        case .threatenOutsiders: "Threatening Outsiders"
        case .seekOutsiders: "Entreating with Outsiders"
        case .restAndRecover: "Resting and Recovering"
        case .sabotageOtherClans: "Sabotaging other Clans"
        case .aidOtherClans: "Helping Other Clans"
        case .raidOtherClans: "Raiding Other Clans"
        case .hoarding: "Hoarding Resources"
        }
    }

    var summary: String {
        switch self {
        case .businessAsUsual: "The Clan has no specific focus and won't get any bonuses."
        case .hunting: "Each working warrior (including deputy and leader) and each working apprentice gathers additional prey each moon."
        case .herbGathering: "Each medicine cat and medicine cat apprentice gathers additional herbs each moon with extra help from the warriors."
        case .threatenOutsiders: "The warriors' threatening behaviour worsens the Clan's relationship with cats outside the Clan."
        case .seekOutsiders: "The warriors sow seeds of friendship, improving the Clan's relationship with cats outside the Clan."
        case .restAndRecover: "The Clan takes more care with its tasks, so injuries, illnesses and outbreaks are less common."
        case .sabotageOtherClans: "Mediators and warriors work together to undermine the chosen Clans."
        case .aidOtherClans: "Mediators and warriors work together to help the chosen Clans with whatever they need."
        case .raidOtherClans: "Warriors cross borders for prey and herbs, at the cost of injuries and relations with the chosen Clans."
        case .hoarding: "Warriors stockpile prey and herbs regardless of their own safety, so injuries and illnesses increase."
        }
    }

    var targetsOtherClans: Bool { [.sabotageOtherClans, .aidOtherClans, .raidOtherClans].contains(self) }
    var needsPreyAndHerbs: Bool { [.hunting, .herbGathering, .raidOtherClans, .hoarding].contains(self) }
    var needsMediator: Bool { self == .sabotageOtherClans || self == .aidOtherClans }
    var needsMedicineCat: Bool { self == .herbGathering }
}

extension Clan {
    /// Why a focus can't be chosen right now.
    enum FocusBlock: Sendable {
        case needsPreyAndHerbs, needsMediator, needsMedicineCat, needsDeputy
    }

    var canChangeFocus: Bool { focusChangedAt.map { $0 + ClanFocus.duration <= age } ?? true }
    var moonsUntilFocusChange: Int { max(0, (focusChangedAt ?? age) + ClanFocus.duration - age) }

    /// Clangen's warriors' den buttons: a working deputy is needed to set any focus.
    func focusBlock(_ focus: ClanFocus) -> FocusBlock? {
        let working = living.filter { !$0.isNotWorking }
        if focus.needsPreyAndHerbs, !preyAndHerbs { return .needsPreyAndHerbs }
        if focus.needsMediator, !working.contains(where: { $0.rank.isMediator }) { return .needsMediator }
        if focus.needsMedicineCat, !working.contains(where: { [.medicineCat, .medicineApprentice].contains($0.rank) }) { return .needsMedicineCat }
        if !isAlive(deputy) || self[deputy]?.isNotWorking == true { return .needsDeputy }
        return nil
    }
}
