import SwiftUI

/// Switches between camp and list, and in camp toggles den labels and notes who isn't shown.
struct ClanViewBar: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: ClanViewMode
    @Binding var showsDenLabels: Bool

    var body: some View {
        HStack(spacing: 16) {
            Picker("View", selection: $mode) {
                ForEach(ClanViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            if mode == .camp {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        notes
                        Spacer(minLength: 0)
                        labelsToggle
                    }
                    HStack(spacing: 16) {
                        Spacer(minLength: 0)
                        labelsToggle
                    }
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var notes: some View {
        let newborns = model.clan?.living.count(where: { $0.rank == .newborn }) ?? 0
        if newborns > 0 {
            Label(newborns == 1 ? "1 newborn in the nursery" : "\(newborns) newborns in the nursery", systemImage: "moon.zzz.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        if model.campOverflow > 0 {
            Button(model.campOverflow == 1 ? "+1 more cat" : "+\(model.campOverflow) more cats", action: showList)
                .font(.subheadline.bold())
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .fixedSize()
                .accessibilityHint("Shows every cat in the list")
        }
    }

    private var labelsToggle: some View {
        Toggle("Show den labels", isOn: $showsDenLabels)
            .font(.subheadline)
            .fixedSize()
    }

    private func showList() {
        mode = .list
    }
}
