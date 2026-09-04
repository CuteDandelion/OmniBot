import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var path = UserDefaults.standard.string(forKey: CodexProcess.pathDefaultsKey) ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex CLI")
                .font(Tokens.body.weight(.semibold))
                .foregroundStyle(Tokens.fg)

            Text("Binary path override. Leave empty to use `codex` on PATH.")
                .font(Tokens.caption)
                .foregroundStyle(Tokens.muted)

            HStack(spacing: 8) {
                styledField {
                    TextField("/usr/local/bin/codex", text: $path)
                        .textFieldStyle(.plain)
                        .font(Tokens.body)
                        .foregroundStyle(Tokens.fg)
                        .onSubmit { save() }
                        .accessibilityIdentifier("codex-path-field")
                }
                Button("Choose…") { choose() }
                    .font(Tokens.body)
                    .accessibilityIdentifier("codex-path-choose")
            }

            HStack {
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("codex-path-save")
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Tokens.subtle)
        .navigationTitle("Settings")
        .onAppear {
            path = UserDefaults.standard.string(forKey: CodexProcess.pathDefaultsKey) ?? ""
        }
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

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose the Codex CLI binary"
        let current = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
        save()
    }

    private func save() {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        path = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: CodexProcess.pathDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: CodexProcess.pathDefaultsKey)
        }
        Task { await session.retry() }
    }
}
