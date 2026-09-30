import SwiftUI

struct ClanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isShowingLog = false
    @State private var isShowingCompactLog = Self.startsOnMoons
    @AppStorage("clanView") private var mode = ClanViewMode.camp
    @AppStorage("denLabels") private var showsDenLabels = true

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if sizeClass == .compact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear(perform: model.rollCamp)
            .onChange(of: mode) { _, mode in
                if mode == .camp { model.rollCamp() }
            }
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
            .sheet(isPresented: $model.isShowingLeaderDen) {
                LeaderDenSheet()
            }
            .sheet(isPresented: $model.isShowingAfterlife) {
                AfterlifeSheet()
            }
            .sheet(isPresented: $model.isShowingSettings) {
                ClanSettingsSheet()
            }
            .sheet(isPresented: $model.isShowingAllegiances) {
                AllegiancesSheet()
            }
            .sheet(isPresented: $model.isShowingFocus) {
                WarriorsDenSheet()
            }
            .sheet(isPresented: $model.isShowingMediation) {
                MediationSheet(mediator: model.mediationMediator)
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

    private var regularLayout: some View {
        VStack(spacing: 0) {
            ClanHeader(showsLogButton: sizeClass != .regular, showLog: showLog)
            Divider()
            GeometryReader { proxy in
                if sizeClass != .regular {
                    mainColumn
                } else if mode == .camp && proxy.size.width < proxy.size.height {
                    VStack(spacing: 0) {
                        mainColumn
                            .frame(height: min(proxy.size.height * 0.72, proxy.size.width * 0.875 + 52))
                        Divider()
                        MoonLogPanel()
                    }
                } else {
                    HStack(spacing: 0) {
                        mainColumn
                        Divider()
                        MoonLogPanel()
                            .frame(width: 360)
                    }
                }
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            CompactClanHeader(tab: compactTab)
            Divider()
            switch compactTab.wrappedValue {
            case .camp:
                CampView()
                    .overlay(alignment: .top) {
                        CompactCampBar(showsDenLabels: $showsDenLabels, showCats: showCats)
                    }
            case .cats:
                CatRoster()
            case .moons:
                MoonLogPanel()
            }
            Divider()
            CompactClanActions()
        }
    }

    private var compactTab: Binding<CompactClanTab> {
        Binding {
            isShowingCompactLog ? .moons : mode == .camp ? .camp : .cats
        } set: { tab in
            isShowingCompactLog = tab == .moons
            switch tab {
            case .camp: mode = .camp
            case .cats: mode = .list
            case .moons: break
            }
        }
    }

    private static var startsOnMoons: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "clanView") == "moons"
        #else
        false
        #endif
    }

    private func showCats() {
        mode = .list
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            ClanViewBar(mode: $mode, showsDenLabels: $showsDenLabels)
            switch mode {
            case .camp: CampView()
            case .list: CatRoster()
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
