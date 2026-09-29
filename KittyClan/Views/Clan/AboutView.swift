import SwiftUI

struct AboutView: View {
    var body: some View {
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
    }
}
