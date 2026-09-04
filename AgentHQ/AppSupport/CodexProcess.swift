import Foundation

enum CodexProcess {
    static let pathDefaultsKey = "codexPath"

    static var applicationSupportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentHQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var handoffSocketURL: URL {
        applicationSupportDirectory.appendingPathComponent("Handoff.sock")
    }

    static func resolveExecutable(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let override = defaults.string(forKey: pathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fileExists(path) ? URL(fileURLWithPath: path) : nil
        }
        return findOnPATH(name: "codex", path: environment["PATH"] ?? "", fileExists: fileExists)
    }

    static func findOnPATH(
        name: String,
        path: String,
        fileExists: (String) -> Bool
    ) -> URL? {
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(name)
            if fileExists(candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func makeExtraConfig(mcpExecutable: URL, socketPath: String) -> [String: String] {
        [
            "mcp_servers.agenthq.command": tomlString(mcpExecutable.path),
            "mcp_servers.agenthq.args": "[\"--mcp\"]",
            "mcp_servers.agenthq.env.AGENTHQ_HANDOFF_SOCKET": tomlString(socketPath),
            "mcp_servers.agenthq.startup_timeout_sec": "8",
        ]
    }

    private static func tomlString(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
