import SwiftUI

struct PageSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.presentationSizing(.page)
        } else {
            content.presentationDetents([.large])
        }
    }
}
