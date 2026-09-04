import SwiftUI

@main
struct AgentHQApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
            } detail: {
                ChatView()
            }
            .background(Tokens.canvas)
        }
        .defaultSize(width: 960, height: 640)
    }
}
