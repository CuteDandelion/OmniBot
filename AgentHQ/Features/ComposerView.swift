import CodexClient
import SwiftData
import SwiftUI

struct ComposerView: View {
    @Bindable var agent: Agent
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var modelContext
    @State private var draft = ""
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Message \(agent.name)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Tokens.body)
                .foregroundStyle(Tokens.fg)
                .lineLimit(3...8)
                .accessibilityIdentifier("composer-input")
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) {
                        return .ignored
                    }
                    if isRunning { return .handled }
                    send()
                    return .handled
                }

            HStack(spacing: 8) {
                Picker("Model", selection: modelBinding) {
                    ForEach(modelOptions, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(Tokens.body)
                .accessibilityIdentifier("composer-model")

                Picker("Effort", selection: effortBinding) {
                    ForEach(effortOptions, id: \.reasoningEffort) { effort in
                        Text(effort.reasoningEffort).tag(effort.reasoningEffort)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(Tokens.body)
                .disabled(effortOptions.isEmpty)
                .accessibilityIdentifier("composer-effort")

                Spacer(minLength: 0)

                Button(isRunning ? "Stop" : "Send") {
                    if isRunning {
                        Task { await session.interruptTurn(for: agent) }
                    } else {
                        send()
                    }
                }
                .font(Tokens.body)
                .disabled(isRunning ? false : !canSend)
                .accessibilityIdentifier(isRunning ? "composer-stop" : "composer-send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Tokens.subtle)
        .onAppear { reconcileEffortIfNeeded() }
        .onChange(of: session.models) { _, _ in reconcileEffortIfNeeded() }
        .alert("Couldn’t save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var isRunning: Bool {
        session.isTurnActive(for: agent.id)
    }

    private var canSend: Bool {
        session.connectionState == .ready
            && agent.threadId != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelOptions: [ModelInfo] {
        var items = session.models
        if !agent.model.isEmpty && !items.contains(where: { $0.id == agent.model }) {
            items.insert(ModelInfo(id: agent.model, displayName: agent.model), at: 0)
        }
        return items
    }

    private var effortOptions: [ReasoningEffort] {
        if let model = session.models.first(where: { $0.id == agent.model }) {
            return model.supportedReasoningEfforts
        }
        if agent.reasoningEffort.isEmpty { return [] }
        return [ReasoningEffort(reasoningEffort: agent.reasoningEffort, description: agent.reasoningEffort)]
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { agent.model },
            set: { newValue in
                agent.model = newValue
                reconcileEffortIfNeeded(forceDefault: true)
                persist()
            }
        )
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: { agent.reasoningEffort },
            set: { newValue in
                agent.reasoningEffort = newValue
                persist()
            }
        )
    }

    private func reconcileEffortIfNeeded(forceDefault: Bool = false) {
        let options = effortOptions.map(\.reasoningEffort)
        guard !options.isEmpty else { return }
        if forceDefault || !options.contains(agent.reasoningEffort) {
            if let model = session.models.first(where: { $0.id == agent.model }),
               let defaultEffort = model.defaultReasoningEffort,
               options.contains(defaultEffort) {
                agent.reasoningEffort = defaultEffort
            } else if let first = options.first {
                agent.reasoningEffort = first
            }
            persist()
        }
    }

    private func persist() {
        do {
            try modelContext.save()
            UserDefaults.standard.set(agent.model, forKey: "agentHQ.lastModel")
            UserDefaults.standard.set(agent.reasoningEffort, forKey: "agentHQ.lastEffort")
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard agent.threadId != nil, !text.isEmpty, !isRunning else { return }
        draft = ""
        Task { await session.send(text, from: agent) }
    }
}
