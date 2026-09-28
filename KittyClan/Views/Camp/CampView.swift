import SwiftUI

/// Clangen's camp: the Clan's cats sitting around the seasonal camp art, on an 800×700 canvas
/// scaled to fit, with a blurred copy of the art filling the space around it.
struct CampView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("denLabels") private var showsDenLabels = true
    @State private var backdrop: CampBackdrop?

    var body: some View {
        if let clan = model.clan, let camps = model.assets?.camps {
            let url = camps.background(camp: clan.camp, season: clan.season, dark: colorScheme == .dark)
            GeometryReader { proxy in
                let scale = min(proxy.size.width / CampLayout.canvas.width, proxy.size.height / CampLayout.canvas.height)
                CampCanvas(
                    backdrop: backdrop,
                    labels: showsDenLabels ? camps.layouts[clan.camp]?.labels ?? [:] : [:],
                    scale: scale
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background { CampBlurredBackdrop(image: backdrop?.image) }
            .clipped()
            .task(id: url) {
                backdrop = await CampBackdrop.load(url)
            }
        }
    }
}
