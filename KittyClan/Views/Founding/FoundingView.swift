import SwiftUI

struct FoundingView: View {
    @Bindable var founding: FoundingModel

    var body: some View {
        NavigationStack(path: $founding.path) {
            FoundingNameStep(founding: founding)
                .navigationDestination(for: FoundingModel.Step.self) { step in
                    switch step {
                    case .chooseCats: FoundingCatsStep(founding: founding)
                    case .options: FoundingOptionsStep(founding: founding)
                    }
                }
        }
    }
}
