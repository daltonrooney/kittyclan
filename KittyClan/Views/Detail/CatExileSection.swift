import SwiftUI

struct CatExileSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    @State private var isConfirming = false

    var body: some View {
        let name = model.displayName(cat)
        Section {
            Button("Exile \(name)", systemImage: "figure.walk.departure", role: .destructive, action: confirm)
                .disabled(model.isAdvancing)
        } footer: {
            Text("Exiled cats leave the Clan and live as loners.")
        }
        .confirmationDialog("Exile \(name)?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Exile \(name)", role: .destructive, action: exile)
        } message: {
            Text("They can only return if invited back from the Leader's Den.")
        }
        #if DEBUG
        .task {
            if UserDefaults.standard.bool(forKey: "confirmExile") { isConfirming = true }
        }
        #endif
    }

    private func confirm() {
        isConfirming = true
    }

    private func exile() {
        Task { await model.exile(cat.id) }
    }
}
