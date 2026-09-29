import SwiftUI
import UIKit

/// A Clan symbol in Clangen's dark ink, or its pale ink in dark mode, scaled up with crisp pixels.
struct ClanSymbolImage: View {
    let symbol: String?

    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 239 / 255, green: 229 / 255, blue: 206 / 255, alpha: 1)
            : UIColor(red: 87 / 255, green: 76 / 255, blue: 45 / 255, alpha: 1)
    })

    var body: some View {
        Group {
            if let symbol, let image = PresentationArt.shared.symbol(symbol) {
                Image(decorative: image, scale: 1)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.none)
                    .foregroundStyle(Self.ink)
            } else {
                Image(systemName: "pawprint")
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
