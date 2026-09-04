import SwiftData
import SwiftUI

struct SidebarView: View {
    @Binding var selectedAgentID: UUID?
    @Query(sort: \Agent.createdAt, order: .forward) private var agents: [Agent]
    @State private var filterText = ""
    @State private var showingNewAgent = false

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

            List(selection: $selectedAgentID) {
                ForEach(filteredAgents, id: \.id) { agent in
                    AgentRow(agent: agent)
                        .tag(agent.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .overlay(Tokens.border)

            Button(action: { showingNewAgent = true }) {
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
            .accessibilityIdentifier("new-agent-button")
        }
        .background(Tokens.subtle)
        .navigationTitle("Agent HQ")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingNewAgent = true }) {
                    Image(systemName: "plus")
                }
                .help("New agent")
            }
        }
        .sheet(isPresented: $showingNewAgent) {
            NewAgentSheet { id in
                selectedAgentID = id
            }
        }
    }

    private var filteredAgents: [Agent] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return agents }
        return agents.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.displayRole.localizedCaseInsensitiveContains(query)
        }
    }
}
