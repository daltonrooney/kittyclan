import SwiftUI

/// The Clan's options, most of which can change at any time.
struct ClanSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        Section {
                            toggle("Leader chooses a new deputy", systemImage: "person.badge.shield.checkmark.fill", option: \.autoDeputy)
                            toggle("Assign mentors automatically", systemImage: "graduationcap.fill", option: \.assignMentors)
                            toggle("Apprentices graduate at 12 moons", systemImage: "12.circle.fill", option: \.twelveMoonGraduation)
                            toggle("Never retire because of a condition", systemImage: "figure.walk.motion", option: \.noConditionRetirement)
                            toggle("Warriors and elders may become mediators", systemImage: "person.2.wave.2.fill", option: \.becomeMediator)
                        } header: {
                            Text("Roles")
                        } footer: {
                            Text("With these off, you name deputies and mentors yourself, apprentices graduate once they're trained, and cats with lasting conditions may retire early.")
                        }
                        Section {
                            toggle("Romance with former mentors", systemImage: "heart.text.square.fill", option: \.romanceWithFormerMentor)
                            toggle("First cousins may be mates", systemImage: "person.3.fill", option: \.firstCousinMates)
                        } header: {
                            Text("Mates")
                        } footer: {
                            Text("Whether mentors and the cats they trained, or cats who share grandparents, can fall for each other.")
                        }
                        Section {
                            toggle("Mated cats may have affairs", systemImage: "heart.slash.fill", option: \.affairs)
                            toggle("Unmated cats may have kits", systemImage: "heart.circle", option: \.unmatedParentage)
                            toggle("Kits may have an unknown parent", systemImage: "questionmark.circle.fill", option: \.singleParentage)
                            toggle("Pregnancy ignores biology", systemImage: "figure.2.and.child.holdinghands", option: \.sameSexBirth)
                            if !clan.sameSexBirth {
                                toggle("Same-sex mates adopt kits", systemImage: "figure.and.child.holdinghands", option: \.sameSexAdoption)
                            }
                        } header: {
                            Text("Kits")
                                .id("kits")
                        } footer: {
                            Text("Who can have kits with whom. Allowing more pairings makes each one a little less likely.")
                        }
                        Section {
                            toggle("Murders can happen", systemImage: "drop.fill", option: \.allowMurder)
                        } header: {
                            Text("Darker events")
                        } footer: {
                            Text("Cats who bitterly dislike a Clanmate may secretly kill them, and the truth can come out moons later.")
                        }
                        Section {
                            toggle("Allow mass extinction events", systemImage: "flame.fill", option: \.disasters)
                                .tint(.red)
                        } header: {
                            Text("Disasters")
                                .id("disasters")
                        } footer: {
                            Text("Warning: floods, fires, sickness and worse can strike a Clan of more than 15 cats, killing or carrying off many of them at once. Up to a third of the Clan can be lost in a single moon.")
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
                #if DEBUG
                .task {
                    if let section = UserDefaults.standard.string(forKey: "settingsSection") { proxy.scrollTo(section, anchor: .top) }
                }
                #endif
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
