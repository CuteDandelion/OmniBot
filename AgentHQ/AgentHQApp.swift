import SwiftData
import SwiftUI

@main
enum AgentHQMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp") {
            MCPMain.run()
            return
        }
        AgentHQApp.main()
    }
}

struct AgentHQApp: App {
    let container: ModelContainer = AgentHQApp.makeContainer()
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            AgentHQRootView()
                .environmentObject(session)
        }
        .modelContainer(container)
        .defaultSize(width: 960, height: 640)

        Settings {
            SettingsView()
                .environmentObject(session)
        }
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Agent.self, HandoffRecord.self])
        let config: ModelConfiguration
        if isRunningTests {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AgentHQ", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            config = ModelConfiguration(schema: schema, url: support.appendingPathComponent("default.store"))
        }
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}

struct AgentHQRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var session: AppSession
    @Query(sort: \Agent.createdAt, order: .forward) private var agents: [Agent]

    private var rosterToken: String {
        agents.map { "\($0.id.uuidString)|\($0.name)|\($0.displayRole)" }.joined(separator: ";")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner = session.banner {
                HStack(spacing: 8) {
                    Text(banner)
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.attention)
                    Spacer(minLength: 0)
                    Button("Retry") {
                        Task { await session.retry() }
                    }
                    .font(Tokens.caption)
                    .accessibilityIdentifier("banner-retry")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Tokens.subtle)
                .overlay(alignment: .bottom) {
                    Tokens.border.frame(height: 1)
                }
                .accessibilityIdentifier("codex-banner")
            }

            NavigationSplitView {
                SidebarView(selectedAgentID: $session.selectedAgentID)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            } detail: {
                ChatView(selectedAgentID: session.selectedAgentID)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tokens.canvas)
        .task {
            session.configureHandoff(modelContext: modelContext)
            session.publishRoster(agents)
            await session.start()
        }
        .onChange(of: rosterToken) { _, _ in
            session.publishRoster(agents)
        }
        .sheet(isPresented: Binding(
            get: { session.pendingApproval != nil },
            set: { _ in }
        )) {
            ApprovalSheet()
                .environmentObject(session)
                .environment(\.modelContext, modelContext)
                .interactiveDismissDisabled()
        }
        .onAppear {
            #if DEBUG
            DebugSmoke.runIfNeeded(modelContext: modelContext, session: session)
            #endif
        }
    }
}
