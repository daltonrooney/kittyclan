import Foundation

extension Double {
    /// Prey counts, which can be half pieces: "42" or "28.5".
    var preyAmount: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}
