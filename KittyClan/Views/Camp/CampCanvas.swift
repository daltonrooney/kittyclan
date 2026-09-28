import SwiftUI

/// The camp art stretched to the scaled 800×700 canvas, with cats and den labels at their canvas points.
struct CampCanvas: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let backdrop: CampBackdrop?
    let labels: [Den: CGPoint]
    let scale: CGFloat

    var body: some View {
        let living = Dictionary(uniqueKeysWithValues: (model.clan?.living ?? []).map { ($0.id, $0) })
        ZStack(alignment: .topLeading) {
            background
                .frame(width: CampLayout.canvas.width * scale, height: CampLayout.canvas.height * scale)
                .accessibilityHidden(true)
            ForEach(model.campPlacements) { placement in
                if let cat = living[placement.id] {
                    CampCatButton(cat: cat, shade: backdrop?.shade(at: placement.point), size: 50 * scale)
                        .offset(x: placement.point.x * scale, y: placement.point.y * scale)
                }
            }
            ForEach(Den.allCases, id: \.self) { den in
                if let point = labels[den] {
                    CampDenLabel(den: den)
                        .offset(x: point.x * scale, y: point.y * scale)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if let backdrop {
            Image(decorative: backdrop.image, scale: 1)
                .resizable()
                .interpolation(.none)
        } else {
            colorScheme == .dark
                ? Color(red: 57 / 255, green: 50 / 255, blue: 36 / 255)
                : Color(red: 206 / 255, green: 194 / 255, blue: 168 / 255)
        }
    }
}
