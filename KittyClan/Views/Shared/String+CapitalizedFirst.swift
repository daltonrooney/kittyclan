import Foundation

extension String {
    /// Capitalizes only the first letter, leaving names inside the text alone.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
