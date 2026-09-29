import SwiftUI

/// This device's music and sound settings, shared by every Clan.
struct AudioSettingsSection: View {
    @Environment(AudioDirector.self) private var audio

    var body: some View {
        @Bindable var audio = audio
        Section {
            Toggle(isOn: $audio.isMusicOn) {
                Label("Music", systemImage: "music.note")
            }
            if audio.isMusicOn {
                volume("Music volume", systemImage: "music.quarternote.3", value: $audio.musicVolume)
                volume("Ambience volume", systemImage: "leaf", value: $audio.ambienceVolume)
            }
            Toggle(isOn: $audio.isSoundEffectsOn) {
                Label("Sound effects", systemImage: "speaker.wave.2.fill")
            }
            if audio.isSoundEffectsOn {
                volume("Sound effects volume", systemImage: "speaker.wave.1", value: $audio.soundVolume)
            }
        } header: {
            Text("Sound")
        } footer: {
            Text(audio.library.hasAudioFiles
                ? "Music and ambience change with your Clan's home and the season. These settings apply to all your Clans."
                : "This version of KittyClan doesn't include ClanGen's music and sounds yet. These settings apply to all your Clans.")
        }
    }

    private func volume(_ title: String, systemImage: String, value: Binding<Double>) -> some View {
        LabeledContent {
            Slider(value: value, in: 0...1)
                .frame(maxWidth: 260)
                .accessibilityLabel(title)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
