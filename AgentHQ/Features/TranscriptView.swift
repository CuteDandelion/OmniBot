import SwiftUI

struct TranscriptView: View {
    var items: [ChatItem]
    var viewerAgentID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        ChatItemRow(item: item, viewerAgentID: viewerAgentID)
                            .id(item.id)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Tokens.canvas)
            .onChange(of: scrollToken) { _, _ in
                if let last = items.last?.id {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .accessibilityIdentifier("transcript")
    }

    private var scrollToken: String {
        items.map { item in
            switch item.kind {
            case .user(let text): return "u:\(item.id):\(text)"
            case .assistant(let text): return "a:\(item.id):\(text)"
            case .working(let detail): return "w:\(detail ?? "")"
            case .diff(let path, let summary): return "d:\(path):\(summary)"
            case .handoff(let record): return "h:\(record.id.uuidString):\(record.status)"
            }
        }.joined(separator: "\n")
    }
}

private struct ChatItemRow: View {
    var item: ChatItem
    var viewerAgentID: UUID?

    var body: some View {
        switch item.kind {
        case .user(let text):
            VStack(alignment: .leading, spacing: 4) {
                Text("You")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                Text(text)
                    .font(Tokens.body)
                    .foregroundStyle(Tokens.fg)
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("chat-item-user")
        case .assistant(let text):
            Text(markdown(text))
                .font(Tokens.body)
                .foregroundStyle(Tokens.fg)
                .textSelection(.enabled)
                .accessibilityIdentifier("chat-item-assistant")
        case .working(let detail):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(detail.map { "Working · \($0)" } ?? "Working")
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityIdentifier("chat-item-working")
        case .diff(let path, let summary):
            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Tokens.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(summary)
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.subtle)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.cardRadius)
                    .stroke(Tokens.border, lineWidth: 1)
            )
            .accessibilityIdentifier("chat-item-diff")
        case .handoff(let record):
            if let viewerAgentID {
                HandoffCard(record: record, viewerAgentID: viewerAgentID)
            } else {
                Text(record.brief)
                    .font(Tokens.caption)
                    .foregroundStyle(Tokens.muted)
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
