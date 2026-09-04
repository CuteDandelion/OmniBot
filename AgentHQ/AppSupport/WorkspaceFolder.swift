import AppKit

enum WorkspaceFolder {
    static func choose(currentPath: String = "") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a workspace folder"
        if !currentPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentPath)
        }
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }
}
