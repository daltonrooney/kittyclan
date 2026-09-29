import SwiftUI

/// The Clan's options, most of which can change at any time.
struct ClanSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let clan = model.clan {
                    Section {
                        LabeledContent {
                            Text(clan.biome.label(camp: clan.camp))
                        } label: {
                            Label("Home", systemImage: clan.biome.symbol)
                        }
                    } header: {
                        Text("Territory")
                    } footer: {
                        Text("Chosen when the Clan was founded.")
                    }
                    Section {
                        LabeledContent {
                            Text(clan.preyAndHerbs ? "On" : "Off")
                        } label: {
                            Label("Prey and herbs", systemImage: "fish.fill")
                        }
                        if clan.preyAndHerbs {
                            toggle("Cats can starve", systemImage: "exclamationmark.triangle.fill", option: \.canStarve)
                        }
                    } header: {
                        Text("Supplies")
                    } footer: {
                        Text(clan.preyAndHerbs
                            ? "The Clan hunts to fill a fresh-kill pile and heals with herbs. This was chosen when the Clan was founded."
                            : "The Clan doesn't track prey or herbs. This was chosen when the Clan was founded.")
                    }
                    Section("Clan life") {
                        toggle("Warriors and elders may become mediators", systemImage: "person.2.wave.2.fill", option: \.becomeMediator)
                        toggle("Same-sex mates adopt kits", systemImage: "figure.and.child.holdinghands", option: \.sameSexAdoption)
                    }
                    Section {
                        toggle("Murders can happen", systemImage: "drop.fill", option: \.allowMurder)
                    } header: {
                        Text("Darker events")
                    } footer: {
                        Text("Cats who bitterly dislike a Clanmate may secretly kill them, and the truth can come out moons later.")
                    }
                    Section {
                        toggle("Dead cats fade", systemImage: "aqi.low", option: \.fading)
                    } header: {
                        Text("Afterlife")
                    } footer: {
                        Text("Long-dead cats fade from the afterlife unless you keep them from fading.")
                    }
                }
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About KittyClan", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Clan Settings")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, option: WritableKeyPath<Clan, Bool>) -> some View {
        Toggle(isOn: binding(option)) {
            Label(title, systemImage: systemImage)
        }
        .disabled(model.isAdvancing)
    }

    private func binding(_ option: WritableKeyPath<Clan, Bool>) -> Binding<Bool> {
        Binding {
            model.clan?[keyPath: option] ?? false
        } set: { on in
            Task { await model.setOption(option, on) }
        }
    }
}
