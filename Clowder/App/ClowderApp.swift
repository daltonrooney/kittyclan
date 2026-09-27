import SwiftUI

@main
struct ClowderApp: App {
    @State private var model = ClanModel()

    var body: some Scene {
        WindowGroup {
            CatGridView(model: model)
        }
    }
}
