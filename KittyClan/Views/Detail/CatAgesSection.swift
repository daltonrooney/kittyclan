import SwiftUI

struct CatAgesSection: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let cat: Cat

    var body: some View {
        Section("Through the moons") {
            ScrollView(.horizontal) {
                HStack(spacing: sizeClass == .compact ? 8 : 16) {
                    ForEach(CatAge.allCases, id: \.self) { age in
                        VStack {
                            CatSprite(cat: cat, age: age)
                                .frame(width: sizeClass == .compact ? 72 : 96)
                                .background(age == cat.age ? Color.accentColor.opacity(0.15) : .clear, in: .rect(cornerRadius: 10))
                            Text(age.label)
                                .font(.caption.bold())
                                .foregroundStyle(age == cat.age ? .primary : .secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("As \(age.label.lowercased() == "adult" ? "an adult" : "a \(age.label.lowercased())")")
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
        }
    }
}
