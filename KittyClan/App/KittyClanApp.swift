import SwiftUI

@main
struct KittyClanApp: App {
    @State private var model = AppModel()
    @State private var audio = AudioDirector()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(audio)
        }
    }
}
