import SwiftUI

struct SidebarView: View {
    @State private var filterText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent HQ")
                    .font(Tokens.body.weight(.semibold))
                    .foregroundStyle(Tokens.fg)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                TextField("Filter", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Tokens.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.cardRadius)
                    .stroke(Tokens.border, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List {
                EmptyView()
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .overlay(Tokens.border)

            Button(action: newAgent) {
                Label("New agent", systemImage: "plus")
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New agent")
        }
        .background(Tokens.subtle)
        .navigationTitle("Agent HQ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: newAgent) {
                    Image(systemName: "plus")
                }
                .help("New agent")
            }
        }
    }

    private func newAgent() {}
}
