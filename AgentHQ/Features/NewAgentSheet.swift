import SwiftData
import SwiftUI

struct NewAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    var onCreated: (UUID) -> Void = { _ in }

    @State private var name = ""
    @State private var role: RolePreset = .chiefOfStaff
    @State private var customRoleTitle = ""
    @State private var systemMessage = RolePreset.chiefOfStaff.developerInstructions
    @State private var mascot: MascotKind = RolePreset.chiefOfStaff.defaultMascot
    @State private var userPickedMascot = false
    @State private var workspacePath = ""
    @State private var saveError: String?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !workspacePath.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
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
                    }

                    fieldLabel("System message")
                    styledField {
                        TextField("Role instructions for Codex…", text: $systemMessage, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(Tokens.body)
                            .foregroundStyle(Tokens.fg)
                            .lineLimit(4...8)
                            .accessibilityIdentifier("system-message-field")
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
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .accessibilityIdentifier("create-agent-button")
            }
            .padding(.top, 12)
        }
        .padding(20)
        .frame(width: 420)
        .frame(minHeight: 520, maxHeight: 720)
        .background(Tokens.subtle)
        .onChange(of: role) { oldValue, newValue in
            if !userPickedMascot {
                mascot = newValue.defaultMascot
            }
            let trimmed = systemMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == oldValue.developerInstructions {
                systemMessage = newValue.developerInstructions
            }
        }
        .alert("Couldn’t create agent", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
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
        let instructions = Agent.seededInstructions(for: role, override: systemMessage)
        let model = Self.resolvedModel
        let effort = Self.resolvedEffort
        let agent = Agent(
            name: trimmedName,
            role: role,
            customRoleTitle: role == .custom && !trimmedTitle.isEmpty ? trimmedTitle : nil,
            customInstructions: instructions,
            mascot: mascot,
            workspacePath: workspacePath,
            model: model,
            reasoningEffort: effort
        )
        modelContext.insert(agent)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(agent)
            saveError = error.localizedDescription
            return
        }
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

