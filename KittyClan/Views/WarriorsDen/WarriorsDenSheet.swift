import SwiftUI

/// Clangen's warriors' den: what the Clan's warriors focus on for the next few moons.
struct WarriorsDenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ClanFocus.businessAsUsual
    @State private var targets: [OtherClan.ID] = []
    @State private var message: FocusMessage?

    var body: some View {
        NavigationStack {
            List {
                if let clan = model.clan {
                    CurrentFocusSection(clan: clan)
                    if clan.focusBlock(.businessAsUsual) == .needsDeputy {
                        Section {
                            DenNoticeRow(
                                text: "Without a healthy deputy, the Clan has nobody to focus the warriors.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                        }
                    }
                    Section("Focus") {
                        ForEach(ClanFocus.allCases.filter { clan.focusBlock($0) != .needsPreyAndHerbs }, id: \.self) { focus in
                            FocusRow(
                                focus: focus,
                                reason: reason(clan.focusBlock(focus)),
                                isCurrent: focus == clan.focus,
                                isSelected: focus == selection
                            ) {
                                select(focus)
                            }
                        }
                    }
                    if selection.targetsOtherClans {
                        Section {
                            ForEach(clan.otherClans) { other in
                                OtherClanRow(clan: other, isAtWar: clan.war.enemy == other.id, isSelected: targets.contains(other.id)) {
                                    toggle(other.id)
                                }
                            }
                        } header: {
                            Text("Which Clans?")
                        } footer: {
                            Text("Choose at least one Clan.")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                FocusChangeBar(message: message, canChange: canChange, change: change)
            }
            .navigationTitle("Warriors' Den")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .modifier(PageSheetSizing())
        .onAppear(perform: selectCurrent)
        #if DEBUG
        .onAppear(perform: applyDebugArguments)
        #endif
    }

    private var canChange: Bool {
        guard let clan = model.clan, clan.canChangeFocus, clan.focusBlock(selection) == nil, !model.isAdvancing else { return false }
        if selection.targetsOtherClans, targets.isEmpty { return false }
        return selection != clan.focus || (selection.targetsOtherClans && targets != clan.focusTargets)
    }

    private func reason(_ block: Clan.FocusBlock?) -> String? {
        switch block {
        case .needsMediator: "Requires a mediator"
        case .needsMedicineCat: "Requires a medicine cat"
        case .needsDeputy, .needsPreyAndHerbs, nil: nil
        }
    }

    private func selectCurrent() {
        guard let clan = model.clan else { return }
        selection = clan.focus
        targets = clan.focusTargets
    }

    private func select(_ focus: ClanFocus) {
        withAnimation(.snappy) { selection = focus }
        message = nil
    }

    private func toggle(_ id: OtherClan.ID) {
        if let index = targets.firstIndex(of: id) {
            targets.remove(at: index)
        } else {
            targets.append(id)
        }
        message = nil
    }

    #if DEBUG
    /// `-focusPick <focus>` selects a focus (and the first other Clan); `-focusChange YES` then changes to it.
    private func applyDebugArguments() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: "focusPick"), let focus = ClanFocus(rawValue: raw) else { return }
        selection = focus
        if focus.targetsOtherClans, let first = model.clan?.otherClans.first { targets = [first.id] }
        if defaults.bool(forKey: "focusChange") { change() }
    }
    #endif

    private func change() {
        let focus = selection
        let chosen = focus.targetsOtherClans ? targets : []
        Task {
            if await model.setFocus(focus, targets: chosen) {
                message = FocusMessage(text: "From next moon, the warriors will focus on “\(focus.title)”.", isError: false)
            } else {
                message = FocusMessage(text: "The warriors' focus couldn't be changed.", isError: true)
            }
        }
    }
}

struct FocusMessage: Equatable {
    let text: String
    let isError: Bool
}

private struct CurrentFocusSection: View {
    let clan: Clan

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(clan.focus.title)
                    .font(.title3.bold())
                Text(clan.focus.summary)
                    .foregroundStyle(.secondary)
                if clan.focus.targetsOtherClans {
                    let names = clan.focusTargets.compactMap { clan.otherClan($0)?.name }
                    Label("Involved Clans: \(names.isEmpty ? "none" : names.formatted(.list(type: .and)))", systemImage: "flag.2.crossed.fill")
                        .font(.subheadline)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
            Label(changeText, systemImage: clan.canChangeFocus ? "checkmark.circle" : "hourglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } header: {
            Text("Current focus")
        }
    }

    private var changeText: String {
        let next = clan.canChangeFocus
            ? "can change again now"
            : "next change in \(clan.moonsUntilFocusChange) \(clan.moonsUntilFocusChange == 1 ? "moon" : "moons")"
        guard let moon = clan.focusChangedAt else { return "Focus never changed (\(next))" }
        return "Focus last changed: moon \(moon) (\(next))"
    }
}

private struct FocusRow: View {
    let focus: ClanFocus
    let reason: String?
    let isCurrent: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.indigo : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(focus.title)
                            .font(.headline)
                        if isCurrent {
                            Text("Current")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.indigo.opacity(0.18), in: .capsule)
                        }
                    }
                    Text(focus.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reason {
                        Label(reason, systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .opacity(reason != nil ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct FocusChangeBar: View {
    let message: FocusMessage?
    let canChange: Bool
    let change: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if let message {
                Label(message.text, systemImage: message.isError ? "xmark.octagon.fill" : "checkmark.circle.fill")
                    .foregroundStyle(message.isError ? .red : .primary)
            } else {
                Text("A new focus applies from the next moon and lasts at least \(ClanFocus.duration) moons.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Change Focus", systemImage: "scope", action: change)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!canChange)
        }
        .padding()
        .background(.bar)
    }
}
