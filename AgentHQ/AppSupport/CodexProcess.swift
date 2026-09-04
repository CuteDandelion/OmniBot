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

    static func defaultExtraSearchPaths(home: String = NSHomeDirectory()) -> [String] {
        [
            (home as NSString).appendingPathComponent(".local/bin"),
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]
    }

    static func resolveExecutable(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        extraSearchPaths: [String] = CodexProcess.defaultExtraSearchPaths(),
        loginPATH: (() -> String?)? = nil
    ) -> URL? {
        if let override = defaults.string(forKey: pathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fileExists(path) ? URL(fileURLWithPath: path) : nil
        }

        let envPath = environment["PATH"] ?? ""
        if let found = findOnPATH(name: "codex", path: envPath, fileExists: fileExists) {
            return found
        }

        var seen = Set(envPath.split(separator: ":").map(String.init))
        for directory in extraSearchPaths {
            let expanded = (directory as NSString).expandingTildeInPath
            if seen.contains(expanded) { continue }
            seen.insert(expanded)
            let candidate = URL(fileURLWithPath: expanded, isDirectory: true).appendingPathComponent("codex")
            if fileExists(candidate.path) {
                return candidate
            }
        }

        let login = (loginPATH ?? { CodexProcess.readLoginShellPATH() })()
        if let login, let found = findOnPATH(name: "codex", path: login, fileExists: fileExists) {
            return found
        }
        return nil
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

    static func readLoginShellPATH() -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf '%s' \"$PATH\""]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
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
