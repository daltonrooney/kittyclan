import SwiftUI

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("KittyClan is a game about looking after a Clan of warrior cats, one moon at a time.")
                }
                Section("Credits") {
                    Text("Based on ClanGen by the ClanGen team.")
                    Text("Camp art and cat sprites from ClanGen (CC BY-NC 4.0).")
                    Text("Art is CC BY-NC 4.0; code MPL-2.0.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About KittyClan")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
