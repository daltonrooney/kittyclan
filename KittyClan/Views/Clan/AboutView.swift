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
                Text("Clan symbols by ClanGen's artists, including CrispyLoafCombo, Muxa and TinyWinny, and profile backgrounds from ClanGen (CC BY-NC 4.0).")
                Text("Music and sound design for ClanGen by Sharon Hurvitz and Carl-Isaak Krulewitch. KittyClan plays ClanGen's playlists when the tracks are installed; they aren't included in this version.")
                Text("Art is CC BY-NC 4.0; code MPL-2.0.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About KittyClan")
        .toolbarTitleDisplayMode(.inline)
    }
}
