import SwiftUI

/// Clangen's camp: the Clan's cats sitting around the seasonal camp art on an 800×700 canvas, with a
/// blurred copy of the art filling the space around it. The canvas starts scaled to fit, or zoomed in
/// far enough for cats to be comfortably tappable on small screens, and can be pinched and panned.
struct CampView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("denLabels") private var showsDenLabels = true
    @State private var backdrop: CampBackdrop?
    @State private var zoom: CampZoom?
    @State private var panStart: CampZoom?
    @State private var pinchStart: CampZoom?

    var body: some View {
        if let clan = model.clan, let camps = model.assets?.camps {
            let url = camps.background(biome: clan.biome, camp: clan.camp, season: clan.season, dark: colorScheme == .dark)
            GeometryReader { proxy in
                let size = proxy.size
                let current = (zoom ?? Self.initialZoom(in: size)).clamped(in: size)
                CampCanvas(
                    backdrop: backdrop,
                    labels: showsDenLabels ? camps.layout(biome: clan.biome, camp: clan.camp)?.labels ?? [:] : [:],
                    scale: current.scale
                )
                .offset(current.offset(in: size))
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .contentShape(.rect)
                .gesture(pan(current, in: size))
                .simultaneousGesture(pinch(current, in: size))
                .onChange(of: size) { _, size in
                    zoom = zoom?.clamped(in: size)
                }
            }
            .background { CampBlurredBackdrop(image: backdrop?.image) }
            .clipped()
            .task(id: url) {
                backdrop = await CampBackdrop.load(url)
            }
        }
    }

    private static func initialZoom(in size: CGSize) -> CampZoom {
        var zoom = CampZoom.initial(in: size)
        #if DEBUG
        let scale = UserDefaults.standard.double(forKey: "campZoom")
        if scale > 0 { zoom.scale = scale }
        #endif
        return zoom
    }

    private func pan(_ current: CampZoom, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard pinchStart == nil else { return }
                let start = panStart ?? current.panned(by: CGSize(width: -value.translation.width, height: -value.translation.height))
                panStart = start
                zoom = start.panned(by: value.translation).clamped(in: size)
            }
            .onEnded { value in
                guard let start = panStart else { return }
                panStart = nil
                withAnimation(.easeOut(duration: 0.35)) {
                    zoom = start.panned(by: value.predictedEndTranslation).clamped(in: size)
                }
            }
    }

    private func pinch(_ current: CampZoom, in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = pinchStart ?? current
                pinchStart = start
                panStart = nil
                let anchor = CGPoint(x: value.startAnchor.x * size.width, y: value.startAnchor.y * size.height)
                zoom = start.zoomed(by: value.magnification, around: anchor, in: size).clamped(in: size)
            }
            .onEnded { _ in
                pinchStart = nil
            }
    }
}
