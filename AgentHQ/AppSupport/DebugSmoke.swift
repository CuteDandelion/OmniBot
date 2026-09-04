#if DEBUG
import AppKit
import SwiftData
import SwiftUI

enum DebugSmoke {
    private static var didRun = false

    @MainActor
    static func runIfNeeded(modelContext: ModelContext, selectedAgentID: Binding<UUID?>) {
        guard ProcessInfo.processInfo.environment["AGENTHQ_SMOKE"] == "1" else { return }
        guard !AgentHQApp.isRunningTests else { return }
        guard !didRun else { return }
        didRun = true

        let evidence = URL(fileURLWithPath: "/tmp/agenthq-evidence")
        try? FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)

        let workspace = evidence.appendingPathComponent("workspace")
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let workspacePath = ProcessInfo.processInfo.environment["AGENTHQ_WORKSPACE"] ?? workspace.path

        renderSnapshots(to: evidence)

        if ProcessInfo.processInfo.environment["AGENTHQ_CHAT_PROMPT"] != nil {
            let existing = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
            if let engineer = existing.first(where: { $0.role == .softwareEngineer }) {
                selectedAgentID.wrappedValue = engineer.id
                return
            }
        }

        let ada = Agent(
            name: "Ada",
            role: .chiefOfStaff,
            mascot: .corgi,
            workspacePath: workspacePath,
            model: "gpt-5.6",
            reasoningEffort: "medium"
        )
        let lin = Agent(
            name: "Lin",
            role: .softwareEngineer,
            mascot: RolePreset.softwareEngineer.defaultMascot,
            workspacePath: workspacePath
        )
        modelContext.insert(ada)
        modelContext.insert(lin)
        try? modelContext.save()

        if ProcessInfo.processInfo.environment["AGENTHQ_CHAT_PROMPT"] != nil {
            selectedAgentID.wrappedValue = lin.id
        } else {
            selectedAgentID.wrappedValue = ada.id
            ada.mascot = .frog
            try? modelContext.save()
        }

        let payload: [String: Any] = [
            "ada": [
                "id": ada.id.uuidString,
                "name": ada.name,
                "role": ada.role.rawValue,
                "displayRole": ada.displayRole,
                "defaultMascot": ada.role.defaultMascot.rawValue,
                "mascot": ada.mascot.rawValue,
                "workspace": ada.workspacePath
            ],
            "lin": [
                "id": lin.id.uuidString,
                "name": lin.name,
                "role": lin.role.rawValue,
                "mascot": lin.mascot.rawValue
            ],
            "roleSuggestsOnly": ada.role.defaultMascot != ada.mascot,
            "mascotKinds": MascotKind.allCases.map(\.rawValue)
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: evidence.appendingPathComponent("smoke.json"))
        }
        FileManager.default.createFile(
            atPath: evidence.appendingPathComponent("SMOKE_DONE").path,
            contents: Data("ok\n".utf8)
        )
    }

    @MainActor
    private static func renderSnapshots(to directory: URL) {
        snapshot(MascotCatalogShot().preferredColorScheme(.light), size: CGSize(width: 420, height: 620), url: directory.appendingPathComponent("mascots-light.png"))
        snapshot(MascotCatalogShot().preferredColorScheme(.dark), size: CGSize(width: 420, height: 620), url: directory.appendingPathComponent("mascots-dark.png"))
        snapshot(MascotPickerShot(), size: CGSize(width: 300, height: 160), url: directory.appendingPathComponent("mascot-picker.png"))
        snapshot(
            NewAgentSheet().modelContainer(for: [Agent.self, HandoffRecord.self], inMemory: true),
            size: CGSize(width: 420, height: 470),
            url: directory.appendingPathComponent("new-agent-sheet.png")
        )
    }

    @MainActor
    private static func snapshot<V: View>(_ view: V, size: CGSize, url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

private struct MascotCatalogShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MascotKind.allCases) { kind in
                HStack(spacing: 12) {
                    Text(kind.accessibilityName)
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.muted)
                        .frame(width: 64, alignment: .leading)
                    MascotView(kind: kind, state: .idle, size: 48)
                    MascotView(kind: kind, state: .hover, size: 48)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.canvas)
    }
}

private struct MascotPickerShot: View {
    @State private var selection: MascotKind = .corgi

    var body: some View {
        MascotPicker(selection: $selection)
            .padding(12)
            .background(Tokens.subtle)
    }
}

#endif
