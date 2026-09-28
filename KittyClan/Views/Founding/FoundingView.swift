import SwiftUI

struct FoundingView: View {
    @Bindable var founding: FoundingModel

    var body: some View {
        NavigationStack(path: $founding.path) {
            FoundingNameStep(founding: founding)
                .navigationDestination(for: FoundingModel.Step.self) { _ in
                    FoundingCatsStep(founding: founding)
                }
        }
    }
}
