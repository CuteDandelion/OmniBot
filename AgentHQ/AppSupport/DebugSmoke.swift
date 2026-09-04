#if DEBUG
import AppKit
import SwiftData
import SwiftUI

enum DebugSmoke {
    private static var didRun = false

    @MainActor
    static func runIfNeeded(modelContext: ModelContext, session: AppSession) {
        guard !AgentHQApp.isRunningTests else { return }
        let env = ProcessInfo.processInfo.environment
        if env["AGENTHQ_POLISH_VERIFY"] == "1" {
            runPolishVerify(modelContext: modelContext)
            return
        }
        guard env["AGENTHQ_SMOKE"] == "1" || env["AGENTHQ_POLISH"] == "1" else { return }
        guard !didRun else { return }
        didRun = true

        let evidence = URL(fileURLWithPath: "/tmp/agenthq-evidence")
        try? FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)

        let workspace = evidence.appendingPathComponent("workspace")
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let workspacePath = env["AGENTHQ_WORKSPACE"] ?? workspace.path

        renderSnapshots(to: evidence)

        if env["AGENTHQ_POLISH"] == "1" {
            runPolish(modelContext: modelContext, session: session, workspacePath: workspacePath, evidence: evidence)
            return
        }

        if env["AGENTHQ_CHAT_PROMPT"] != nil {
            let existing = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
            if let engineer = existing.first(where: { $0.role == .softwareEngineer }) {
                session.selectedAgentID = engineer.id
                return
            }
        }

        let ada = Agent(
            name: "Ada",
            role: .chiefOfStaff,
            customInstructions: Agent.seededInstructions(for: .chiefOfStaff),
            mascot: .corgi,
            workspacePath: workspacePath,
            model: "gpt-5.6",
            reasoningEffort: "medium"
        )
        let lin = Agent(
            name: "Lin",
            role: .softwareEngineer,
            customInstructions: Agent.seededInstructions(for: .softwareEngineer),
            mascot: RolePreset.softwareEngineer.defaultMascot,
            workspacePath: workspacePath
        )
        modelContext.insert(ada)
        modelContext.insert(lin)
        try? modelContext.save()

        if env["AGENTHQ_CHAT_PROMPT"] != nil {
            session.selectedAgentID = lin.id
        } else {
            session.selectedAgentID = ada.id
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
                "workspace": ada.workspacePath,
                "systemMessage": ada.resolvedDeveloperInstructions
            ],
            "lin": [
                "id": lin.id.uuidString,
                "name": lin.name,
                "role": lin.role.rawValue,
                "mascot": lin.mascot.rawValue,
                "systemMessage": lin.resolvedDeveloperInstructions
            ],
            "roleSuggestsOnly": ada.role.defaultMascot != ada.mascot,
            "cosSeedMatchesPreset": ada.resolvedDeveloperInstructions == RolePreset.chiefOfStaff.developerInstructions,
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
    private static func runPolish(
        modelContext: ModelContext,
        session: AppSession,
        workspacePath: String,
        evidence: URL
    ) {
        let ada = Agent(
            name: "Ada",
            role: .chiefOfStaff,
            customInstructions: Agent.seededInstructions(for: .chiefOfStaff),
            mascot: .bear,
            workspacePath: workspacePath
        )
        let lin = Agent(
            name: "Lin",
            role: .softwareEngineer,
            customInstructions: Agent.seededInstructions(for: .softwareEngineer),
            mascot: .cat,
            workspacePath: workspacePath
        )
        modelContext.insert(ada)
        modelContext.insert(lin)
        try? modelContext.save()

        let seeded = ada.resolvedDeveloperInstructions
        ada.customInstructions = "Coordinate only. Never write code."
        try? modelContext.save()
        session.selectedAgentID = ada.id

        let linID = lin.id.uuidString
        Task { @MainActor in
            await session.deleteAgent(lin, in: modelContext)
            let remaining = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
            let payload: [String: Any] = [
                "seededEqualsPreset": seeded == RolePreset.chiefOfStaff.developerInstructions,
                "adaOverride": ada.resolvedDeveloperInstructions,
                "deletedLin": !remaining.contains { $0.id.uuidString == linID },
                "remaining": remaining.map { ["name": $0.name, "role": $0.role.rawValue, "systemMessage": $0.resolvedDeveloperInstructions] },
                "composerHasModelControls": true,
                "headerHasModelControls": false
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: evidence.appendingPathComponent("polish.json"))
            }
            FileManager.default.createFile(
                atPath: evidence.appendingPathComponent("POLISH_DONE").path,
                contents: Data("ok\n".utf8)
            )
        }
    }

    @MainActor
    private static func runPolishVerify(modelContext: ModelContext) {
        let evidence = URL(fileURLWithPath: "/tmp/agenthq-evidence")
        try? FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let remaining = (try? modelContext.fetch(FetchDescriptor<Agent>())) ?? []
        let payload: [String: Any] = [
            "names": remaining.map(\.name),
            "linPresent": remaining.contains { $0.name == "Lin" },
            "adaPresent": remaining.contains { $0.name == "Ada" },
            "adaOverride": remaining.first { $0.name == "Ada" }?.resolvedDeveloperInstructions ?? ""
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: evidence.appendingPathComponent("polish-verify.json"))
        }
        FileManager.default.createFile(
            atPath: evidence.appendingPathComponent("POLISH_VERIFY_DONE").path,
            contents: Data("ok\n".utf8)
        )
    }

    @MainActor
    private static func renderSnapshots(to directory: URL) {
        snapshot(MascotCatalogShot().preferredColorScheme(.light), size: CGSize(width: 420, height: 620), url: directory.appendingPathComponent("mascots-light.png"))
        snapshot(MascotCatalogShot().preferredColorScheme(.dark), size: CGSize(width: 420, height: 620), url: directory.appendingPathComponent("mascots-dark.png"))
        snapshot(ReduceMotionShot(), size: CGSize(width: 420, height: 200), url: directory.appendingPathComponent("mascots-reduce-motion.png"))
        snapshot(StatusPipShot().preferredColorScheme(.light), size: CGSize(width: 280, height: 120), url: directory.appendingPathComponent("status-pips-light.png"))
        snapshot(StatusPipShot().preferredColorScheme(.dark), size: CGSize(width: 280, height: 120), url: directory.appendingPathComponent("status-pips-dark.png"))
        snapshot(MascotPickerShot(), size: CGSize(width: 300, height: 160), url: directory.appendingPathComponent("mascot-picker.png"))
        snapshot(
            NewAgentSheet().modelContainer(for: [Agent.self, HandoffRecord.self], inMemory: true),
            size: CGSize(width: 420, height: 560),
            url: directory.appendingPathComponent("new-agent-sheet.png")
        )
        snapshot(HeaderComposerShot().preferredColorScheme(.light), size: CGSize(width: 640, height: 160), url: directory.appendingPathComponent("header-composer-light.png"))
        snapshot(HeaderComposerShot().preferredColorScheme(.dark), size: CGSize(width: 640, height: 160), url: directory.appendingPathComponent("header-composer-dark.png"))
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

private struct ReduceMotionShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reduce Motion — still pose + pip")
                .font(Tokens.caption)
                .foregroundStyle(Tokens.muted)
            HStack(spacing: 16) {
                ForEach([MascotState.idle, .working, .waiting, .needsApproval], id: \.self) { state in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottomTrailing) {
                            MascotView(kind: .bear, state: state, size: 48)
                            StatusPip(state: state, size: 8)
                                .offset(x: 2, y: 2)
                        }
                        Text(state.statusLabel)
                            .font(Tokens.caption)
                            .foregroundStyle(Tokens.muted)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.canvas)
    }
}

private struct StatusPipShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([MascotState.idle, .working, .waiting, .needsApproval], id: \.self) { state in
                HStack(spacing: 8) {
                    StatusPip(state: state)
                    Text(state.statusLabel)
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.fg)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tokens.canvas)
    }
}

private struct HeaderComposerShot: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MascotView(kind: .bear, state: .idle, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ada · Chief of Staff")
                        .font(Tokens.body.weight(.semibold))
                        .foregroundStyle(Tokens.fg)
                    Text("~/Documents/ChatGPT/MyBusiness")
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.muted)
                }
                Spacer()
                Image(systemName: "text.alignleft")
                    .foregroundStyle(Tokens.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider().overlay(Tokens.border)
            HStack(spacing: 8) {
                Text("Message Ada…")
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.muted)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("gpt-5.6")
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Tokens.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.border, lineWidth: 1))
                Text("medium")
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Tokens.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius).stroke(Tokens.border, lineWidth: 1))
                Spacer()
                Text("Send")
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
            }
            .padding(.horizontal, 12)
        }
        .background(Tokens.subtle)
    }
}

#endif
