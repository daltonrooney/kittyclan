import SwiftUI

struct PatrolSheet: View {
    let patrol: PatrolModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch patrol.phase {
                case .picking:
                    PatrolPickerView(patrol: patrol)
                case .encounter(let session):
                    PatrolEncounterView(patrol: patrol, session: session)
                case .result(let session, let result):
                    PatrolResultView(patrol: patrol, session: session, result: result, done: dismiss.callAsFunction)
                }
            }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                if !patrol.isEncounter {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: dismiss.callAsFunction)
                    }
                }
            }
        }
        .modifier(PageSheetSizing())
        .interactiveDismissDisabled(patrol.isEncounter)
    }

    private var title: String {
        switch patrol.phase {
        case .picking: "Patrol"
        case .encounter(let session), .result(let session, _): "\(session.type.label) patrol"
        }
    }
}
