import SwiftUI

struct FoundingNameStep: View {
    @Environment(AppModel.self) private var model
    @Bindable var founding: FoundingModel
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Name your Clan")
                    .font(.largeTitle.bold())
                Text("Every Clan needs a name. Type one or roll the dice.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    TextField("Kitty", text: $founding.name)
                        .focused($isNameFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .onSubmit(next)
                        .fixedSize()
                    Text("Clan")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(minWidth: 320)
                .background(.fill.tertiary, in: .rect(cornerRadius: 20))
                .onTapGesture { isNameFocused = true }

                Button("Random name", systemImage: "dice.fill", action: founding.randomName)
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
            }

            Text("\(founding.name.count) of \(ClanFounding.maxNameLength) letters")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: next) {
                Label("Choose your cats", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
                    .font(.title3.bold())
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .disabled(!founding.isNameValid)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("New Clan")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if model.canCancelFounding {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Your Clans", systemImage: "chevron.backward", action: model.showClanChooser)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private func next() {
        guard founding.isNameValid else { return }
        founding.showCats()
    }
}
