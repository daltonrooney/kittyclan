import SwiftUI

struct ClanMenu: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingNewClan = false

    var body: some View {
        Menu("Clan options", systemImage: "ellipsis.circle") {
            Toggle("Dead cats fade", systemImage: "aqi.low", isOn: fading)
            Toggle("Same-sex mates adopt kits", systemImage: "figure.and.child.holdinghands", isOn: sameSexAdoption)
            Divider()
            Button("About KittyClan", systemImage: "info.circle", action: showAbout)
            Button("Start a new Clan", systemImage: "arrow.counterclockwise", role: .destructive, action: confirmNewClan)
        }
        .confirmationDialog("Start a new Clan?", isPresented: $isConfirmingNewClan, titleVisibility: .visible) {
            Button("Start a new Clan", role: .destructive, action: model.startNewClan)
        } message: {
            Text("\(model.clan?.displayName ?? "Your Clan") and all of its history will be gone forever.")
        }
    }

    private var fading: Binding<Bool> {
        Binding {
            model.clan?.fading ?? true
        } set: { fading in
            Task { await model.setFading(fading) }
        }
    }

    private var sameSexAdoption: Binding<Bool> {
        Binding {
            model.clan?.sameSexAdoption ?? false
        } set: { on in
            Task { await model.setSameSexAdoption(on) }
        }
    }

    private func showAbout() {
        model.isShowingAbout = true
    }

    private func confirmNewClan() {
        isConfirmingNewClan = true
    }
}
