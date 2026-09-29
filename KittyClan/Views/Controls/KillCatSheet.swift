import SwiftUI

/// Clangen's kill window: the player says how the cat died, and a leader can lose every life at once.
struct KillCatSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let cat: Cat

    @State private var reason = ""
    @State private var takesAllLives = true
    @State private var isConfirming = false

    var body: some View {
        let isLeader = model.isLeader(cat)
        let name = model.displayName(cat)
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        CatSprite(cat: cat)
                            .frame(width: 72)
                        VStack(alignment: .leading) {
                            Text(name)
                                .font(.largeTitle.bold())
                            Text(isLeader ? livesText : cat.rank.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    TextField("Reason", text: $reason, prompt: Text(MoonEngine.defaultKillReason), axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("How did this cat die?")
                } footer: {
                    Text("This becomes part of \(name)'s history. Letters, numbers, spaces and simple punctuation only; left empty, it reads \u{201C}\(MoonEngine.defaultKillReason)\u{201D}")
                }
                if isLeader {
                    Section {
                        Toggle("Take all the leader's lives", isOn: $takesAllLives)
                    } footer: {
                        Text(takesAllLives ? "\(name) will lose every remaining life and die." : "\(name) will lose one life.")
                    }
                }
            }
            .navigationTitle("Kill \(name)")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kill", role: .destructive) { isConfirming = true }
                        .tint(.red)
                        .disabled(model.isAdvancing)
                }
            }
            .alert(confirmTitle(name: name, isLeader: isLeader), isPresented: $isConfirming) {
                Button("Cancel", role: .cancel) {}
                Button(isLeader && !takesAllLives ? "Take a Life" : "Kill", role: .destructive, action: kill)
            } message: {
                Text("This can't be undone.")
            }
        }
        .onChange(of: reason) {
            let cleaned = MoonEngine.sanitizedDeathReason(reason)
            if cleaned != reason { reason = cleaned }
        }
        #if DEBUG
        .task {
            guard UserDefaults.standard.bool(forKey: "confirmKill") else { return }
            try? await Task.sleep(for: .seconds(1))
            isConfirming = true
        }
        #endif
    }

    private var livesText: String {
        let lives = model.clan?.leaderLives ?? 1
        return lives == 1 ? "1 life left" : "\(lives) lives left"
    }

    private func confirmTitle(name: String, isLeader: Bool) -> String {
        isLeader && !takesAllLives ? "Take one of \(name)'s lives?" : "Kill \(name)?"
    }

    private func kill() {
        Task {
            await model.kill(cat.id, reason: reason, allLives: takesAllLives)
            dismiss()
        }
    }
}
