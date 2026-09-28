import Foundation

extension Season {
    init(moon: Int) {
        self = Season.allCases[(moon / 3) % 4]
    }

    var symbol: String {
        switch self {
        case .newleaf: "leaf.fill"
        case .greenleaf: "sun.max.fill"
        case .leafFall: "wind"
        case .leafBare: "snowflake"
        }
    }
}
