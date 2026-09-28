import Foundation
import Observation

/// The patrol flow: choosing a type and cats, the encounter, and its result.
@MainActor
@Observable
final class PatrolModel: Identifiable {
    enum Phase {
        case picking
        case encounter(PatrolSession)
        case result(PatrolSession, PatrolResult)
    }

    static let maxCats = 6

    let id = UUID()
    private(set) var type: PatrolType?
    private(set) var selectedIDs: [Cat.ID] = []
    private(set) var phase = Phase.picking
    private(set) var isWorking = false
    var isShowingNoPatrol = false

    @ObservationIgnored private unowned let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var eligible: [Cat] { app.patrolEligible }

    var selectedCats: [Cat] { app.cats(selectedIDs) }

    var hasHealer: Bool { selectedCats.contains(where: \.isHealer) }

    var isFull: Bool { selectedIDs.count >= Self.maxCats }

    var isEncounter: Bool {
        if case .encounter = phase { true } else { false }
    }

    var canStart: Bool { !selectedIDs.isEmpty && !isWorking }

    func isSelected(_ cat: Cat) -> Bool {
        selectedIDs.contains(cat.id)
    }

    /// A medicine cat forces herb gathering, and herb gathering needs one.
    func allows(_ type: PatrolType?) -> Bool {
        if selectedIDs.isEmpty { return true }
        return hasHealer ? type == .herbGathering : type != .herbGathering
    }

    func selectType(_ type: PatrolType?) {
        self.type = type
        if type == .herbGathering {
            selectedIDs.removeAll { !(app.cat($0)?.isHealer ?? false) }
        } else if hasHealer {
            selectedIDs.removeAll { app.cat($0)?.isHealer ?? false }
        }
    }

    func toggle(_ cat: Cat) {
        if let index = selectedIDs.firstIndex(of: cat.id) {
            selectedIDs.remove(at: index)
        } else if !isFull {
            selectedIDs.append(cat.id)
        }
        adjustType()
    }

    /// Adds up to `count` random cats who suit the chosen patrol type.
    func addRandom(_ count: Int) {
        let pool = eligible.filter { cat in
            guard !isSelected(cat) else { return false }
            switch type {
            case .herbGathering: return cat.isHealer
            case nil: return selectedIDs.isEmpty || cat.isHealer == hasHealer
            default: return !cat.isHealer
            }
        }
        let room = Self.maxCats - selectedIDs.count
        selectedIDs += pool.shuffled().prefix(min(count, room)).map(\.id)
        adjustType()
    }

    func clearSelection() {
        selectedIDs.removeAll()
        adjustType()
    }

    func start() async {
        guard canStart else { return }
        isWorking = true
        defer { isWorking = false }
        if let session = await app.startPatrol(selectedIDs, type: type) {
            phase = .encounter(session)
        } else {
            isShowingNoPatrol = true
        }
    }

    func choose(_ choice: PatrolChoice) async {
        guard case .encounter(let session) = phase, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if let result = await app.finishPatrol(session, choice: choice) {
            phase = .result(session, result)
        }
    }

    /// Returns to cat picking with the cats who can still patrol, keeping the patrol type.
    func patrolAgain() {
        selectedIDs.removeAll()
        phase = .picking
        adjustType()
    }

    private func adjustType() {
        if hasHealer {
            type = .herbGathering
        } else if type == .herbGathering, !selectedIDs.isEmpty {
            type = nil
        }
    }
}
