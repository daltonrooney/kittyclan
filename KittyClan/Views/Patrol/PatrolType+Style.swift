import Foundation

extension PatrolType {
    var label: String {
        switch self {
        case .hunting: "Hunting"
        case .border: "Border"
        case .training: "Training"
        case .herbGathering: "Herb gathering"
        }
    }

    var symbol: String {
        switch self {
        case .hunting: "hare.fill"
        case .border: "flag.fill"
        case .training: "figure.martial.arts"
        case .herbGathering: "leaf.fill"
        }
    }
}
