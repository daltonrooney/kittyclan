import SwiftUI

struct CatDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    let catID: Cat.ID

    @State private var action: CatAction?
    @State private var isShowingFamilyTree = false
    @State private var isCeremonyExpanded = CatCeremonySection.expandsByDefault
    @State private var wantsCeremony = false

    var body: some View {
        if let cat = model.cat(catID) {
            let isOutsider = model.isOutsider(cat)
            ScrollViewReader { proxy in
            List {
                Section {
                    CatProfilePortrait(cat: cat)
                        .frame(maxWidth: sizeClass == .compact ? 240 : 300)
                        .frame(maxWidth: .infinity)
                        .grayscale(cat.isDead && cat.afterlife == nil ? 0.7 : 0)
                        .accessibilityLabel("\(model.displayName(cat)), \(cat.age.label)")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    if let thought = model.thought(of: cat) {
                        Text("\u{201C}\(thought)\u{201D}")
                            .font(.title3)
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .accessibilityLabel("Thinking: \(thought)")
                    }
                }
                if cat.isDead {
                    CatAfterlifeSection(cat: cat)
                        .id(DetailSection.afterlife)
                }
                if model.isLeader(cat) {
                    CatCeremonySection(cat: cat, isExpanded: $isCeremonyExpanded)
                        .id(DetailSection.ceremony)
                }
                CatAgesSection(cat: cat)
                CatAboutSection(cat: cat, isOutsider: isOutsider)
                CatActionsSection(cat: cat, open: open)
                    .id(DetailSection.actions)
                CatPreferencesSection(cat: cat)
                    .id(DetailSection.preferences)
                if cat.isDead {
                    CatDeathHistorySection(cat: cat)
                        .id(DetailSection.history)
                } else {
                    CatHealthSection(cat: cat)
                        .id(DetailSection.health)
                    CatDeathHistorySection(cat: cat)
                }
                CatFamilySection(cat: cat, showFamilyTree: showFamilyTree)
                    .id(DetailSection.family)
                if !isOutsider, cat.isAlive {
                    CatRelationshipsSection(cat: cat)
                        .id(DetailSection.relationships)
                }
                CatAppearanceSection(cat: cat)
                if !model.isGuide(cat) {
                    CatLifeStorySection(cat: cat)
                        .id(DetailSection.lifeStory)
                }
                if !isOutsider, cat.isAlive {
                    CatExileSection(cat: cat)
                        .id(DetailSection.exile)
                }
            }
            .sheet(item: $action) {
                if wantsCeremony {
                    wantsCeremony = false
                    isCeremonyExpanded = true
                    withAnimation { proxy.scrollTo(DetailSection.ceremony, anchor: .top) }
                }
            } content: { action in
                sheet(action, for: cat)
            }
            #if DEBUG
            .task { applyDebugArguments(proxy) }
            #endif
            }
            .navigationDestination(isPresented: $isShowingFamilyTree) {
                FamilyTreeView(catID: catID)
            }
            .navigationTitle(cat.isDead ? "\(model.displayName(cat)) (dead)" : model.displayName(cat))
            .toolbarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("This cat has wandered off", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func sheet(_ action: CatAction, for cat: Cat) -> some View {
        switch action {
        case .role: RoleSheet(cat: cat) { wantsCeremony = true }
        case .mentor: MentorSheet(cat: cat)
        case .mate: MateSheet(cat: cat)
        case .adoptiveParents: AdoptiveParentSheet(cat: cat)
        case .gender: GenderSheet(cat: cat)
        case .rename: RenameSheet(cat: cat)
        case .mediate: MediationSheet(mediator: cat.id)
        case .kill: KillCatSheet(cat: cat)
        }
    }

    private func open(_ action: CatAction) {
        self.action = action
    }

    private func showFamilyTree() {
        isShowingFamilyTree = true
    }

    #if DEBUG
    @MainActor private static var didApplyDebugArguments = false

    /// `-detailSection afterlife|history|ceremony|actions|preferences|health|family|relationships|lifeStory|exile` scrolls the detail sheet for screenshots;
    /// `-sheet role|mentor|mate|adopt|gender|rename|mediate|kill|family` opens a control once;
    /// `-confirmKill YES`, `-confirmGuideMove YES` and `-confirmAccessories YES` also show those confirmations.
    private func applyDebugArguments(_ proxy: ScrollViewProxy) {
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "detailSection"), let section = DetailSection(rawValue: name) {
            proxy.scrollTo(section, anchor: .top)
        }
        guard !Self.didApplyDebugArguments, let sheet = defaults.string(forKey: "sheet") else { return }
        Self.didApplyDebugArguments = true
        if sheet == "family" {
            isShowingFamilyTree = true
        } else {
            action = CatAction(rawValue: sheet)
        }
    }
    #endif
}
