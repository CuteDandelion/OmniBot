import SwiftData
import SwiftUI

@main
struct AgentHQApp: App {
    let container: ModelContainer = AgentHQApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            AgentHQRootView()
        }
        .modelContainer(container)
        .defaultSize(width: 960, height: 640)
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
    @State private var selectedAgentID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedAgentID: $selectedAgentID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            ChatView(selectedAgentID: selectedAgentID)
        }
        .background(Tokens.canvas)
        .onAppear {
            #if DEBUG
            DebugSmoke.runIfNeeded(modelContext: modelContext, selectedAgentID: $selectedAgentID)
            #endif
        }
    }
}
