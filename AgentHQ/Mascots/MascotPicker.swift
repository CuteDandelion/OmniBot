import SwiftUI

struct MascotPicker: View {
    @Binding var selection: MascotKind
    var onSelect: ((MascotKind) -> Void)? = nil

    // 48pt mascot + 4pt padding each side; 8pt gutters. Width = 4*56 + 3*8 = 248.
    private let columns = Array(repeating: GridItem(.fixed(56), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(MascotKind.allCases) { kind in
                Button {
                    selection = kind
                    onSelect?(kind)
                } label: {
                    MascotView(kind: kind, state: .idle, size: 48)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.cardRadius)
                                .stroke(selection == kind ? Tokens.accent : Color.clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .help(kind.accessibilityName)
                .accessibilityLabel(kind.accessibilityName)
                .accessibilityAddTraits(selection == kind ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mascot")
        .accessibilityIdentifier("mascot-picker")
    }
}
