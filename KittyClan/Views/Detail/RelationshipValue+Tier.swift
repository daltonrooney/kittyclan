import Foundation

extension RelationshipValue {
    /// The tier word for display, such as "confides in".
    func tierText(for amount: Int) -> String {
        tier(for: amount).replacing("_", with: " ")
    }
}
