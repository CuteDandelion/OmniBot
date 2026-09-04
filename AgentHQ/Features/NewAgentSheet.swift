import AppKit
import SwiftData
import SwiftUI

struct NewAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var onCreated: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var role: RolePreset = .chiefOfStaff
    @State private var customRoleTitle = ""
    @State private var customInstructions = ""
    @State private var mascot: MascotKind = RolePreset.chiefOfStaff.defaultMascot
    @State private var userPickedMascot = false
    @State private var workspacePath = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !workspacePath.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New agent")
                .font(Tokens.body.weight(.semibold))
                .foregroundStyle(Tokens.fg)

            fieldLabel("Name")
            styledField {
                TextField("Ada", text: $name)
                    .textFieldStyle(.plain)
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
                    .accessibilityIdentifier("agent-name-field")
            }

            fieldLabel("Role")
            Picker("Role", selection: $role) {
                ForEach(RolePreset.allCases) { preset in
                    Text(preset.defaultTitle).tag(preset)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(Tokens.body)
            .accessibilityIdentifier("agent-role-picker")

            if role == .custom {
                styledField {
                    TextField("Title (optional)", text: $customRoleTitle)
                        .textFieldStyle(.plain)
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.fg)
                }
                styledField {
                    TextField("What should this agent do?", text: $customInstructions, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.fg)
                        .lineLimit(3...6)
                }
            }

            fieldLabel("Mascot")
            MascotPicker(selection: $mascot) { _ in
                userPickedMascot = true
            }

            fieldLabel("Workspace")
            HStack(spacing: 8) {
                Button("Choose folder…") {
                    if let path = WorkspaceFolder.choose(currentPath: workspacePath) {
                        workspacePath = path
                    }
                }
                .font(Tokens.body)
                .accessibilityIdentifier("choose-folder-button")

                if !workspacePath.isEmpty {
                    Text(Agent.displayPath(workspacePath))
                        .font(Tokens.caption)
                        .foregroundStyle(Tokens.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(workspacePath)
                }
            }

            Spacer(minLength: 8)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("create-agent-button")
            }
        }
        .padding(20)
        .frame(width: 420, height: role == .custom ? 560 : 470)
        .background(Tokens.subtle)
        .onChange(of: role) { _, newValue in
            if !userPickedMascot {
                mascot = newValue.defaultMascot
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(Tokens.caption)
            .foregroundStyle(Tokens.muted)
    }

    private func styledField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Tokens.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.cardRadius)
                    .stroke(Tokens.border, lineWidth: 1)
            )
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = customRoleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBlurb = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = Self.resolvedModel
        let effort = Self.resolvedEffort
        let agent = Agent(
            name: trimmedName,
            role: role,
            customRoleTitle: role == .custom && !trimmedTitle.isEmpty ? trimmedTitle : nil,
            customInstructions: role == .custom && !trimmedBlurb.isEmpty ? trimmedBlurb : nil,
            mascot: mascot,
            workspacePath: workspacePath,
            model: model,
            reasoningEffort: effort
        )
        modelContext.insert(agent)
        try? modelContext.save()
        UserDefaults.standard.set(model, forKey: Self.lastModelKey)
        UserDefaults.standard.set(effort, forKey: Self.lastEffortKey)
        onCreated(agent.id)
        dismiss()
    }

    private static let lastModelKey = "agentHQ.lastModel"
    private static let lastEffortKey = "agentHQ.lastEffort"
    private static let defaultModel = "gpt-5.6"
    private static let defaultEffort = "medium"

    private static var resolvedModel: String {
        let stored = UserDefaults.standard.string(forKey: lastModelKey) ?? ""
        return stored.isEmpty ? defaultModel : stored
    }

    private static var resolvedEffort: String {
        let stored = UserDefaults.standard.string(forKey: lastEffortKey) ?? ""
        return stored.isEmpty ? defaultEffort : stored
    }
}

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

private extension Agent {
    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
