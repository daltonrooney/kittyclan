import SwiftUI

/// Clangen's per-cat toggles for a living Clan cat: no kits and no retirement.
struct CatPreferencesSection: View {
    @Environment(AppModel.self) private var model
    let cat: Cat

    var body: some View {
        if model.isLivingClanCat(cat) {
            Section("Preferences") {
                Toggle(isOn: noKits) {
                    Label("Prevent kits", systemImage: "figure.and.child.holdinghands")
                    Text("Never has or adopts kits.")
                }
                Toggle(isOn: noRetire) {
                    Label("Prevent retirement", systemImage: "figure.walk")
                    Text("Never retires automatically, from age or a lasting condition.")
                }
            }
            .disabled(model.isAdvancing)
        }
    }

    private var noKits: Binding<Bool> {
        Binding { cat.noKits } set: { on in Task { await model.setNoKits(on, for: cat.id) } }
    }

    private var noRetire: Binding<Bool> {
        Binding { cat.noRetire } set: { on in Task { await model.setNoRetire(on, for: cat.id) } }
    }
}
