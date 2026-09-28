import SwiftUI

struct ClanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isShowingLog = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                ClanHeader(showsLogButton: sizeClass != .regular, showLog: showLog)
                Divider()
                if sizeClass == .regular {
                    HStack(spacing: 0) {
                        CatRoster()
                        Divider()
                        MoonLogPanel()
                            .frame(width: 360)
                    }
                } else {
                    CatRoster()
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $model.selectedCat) { cat in
                CatDetailSheet(cat: cat)
            }
            .sheet(item: $model.patrol) { patrol in
                PatrolSheet(patrol: patrol)
            }
            .sheet(isPresented: $model.isShowingSupplies) {
                SuppliesSheet()
            }
            .sheet(isPresented: $isShowingLog) {
                NavigationStack {
                    MoonLogPanel()
                        .navigationTitle("Moon log")
                        .toolbarTitleDisplayMode(.inline)
                }
            }
            .alert("Something went wrong", isPresented: isShowingError) {
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding { model.errorMessage != nil } set: { if !$0 { model.errorMessage = nil } }
    }

    private func showLog() {
        isShowingLog = true
    }
}
