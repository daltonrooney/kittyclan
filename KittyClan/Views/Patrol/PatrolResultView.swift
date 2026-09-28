import SwiftUI

struct PatrolResultView: View {
    let patrol: PatrolModel
    let session: PatrolSession
    let result: PatrolResult
    let done: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PatrolArt(name: result.art ?? session.introArt)
                    .frame(maxWidth: 320)
                Label(result.succeeded ? "The patrol succeeded" : "The patrol didn't go to plan",
                      systemImage: result.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.title2.bold())
                    .foregroundStyle(result.succeeded ? .green : .orange)
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.text.storyText)
                        .font(.title3)
                    if !result.results.isEmpty {
                        Divider()
                        ForEach(result.results.indices, id: \.self) { index in
                            Label(result.results[index], systemImage: "pawprint.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.background, in: .rect(cornerRadius: 16))
                PatrolCatsRow(catIDs: session.cats)
                HStack(spacing: 12) {
                    Button(action: patrol.patrolAgain) {
                        Label("Patrol again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brown)
                    .disabled(patrol.eligible.isEmpty)
                    Button(action: done) {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brown)
                }
                .font(.title3.bold())
                .controlSize(.large)
                .frame(maxWidth: 420)
                if patrol.eligible.isEmpty {
                    Text("Every cat has patrolled this moon.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
    }
}
