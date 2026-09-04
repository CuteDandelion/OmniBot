import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        VStack(spacing: 12) {
            Text(EmptyStateCopy.title(for: session.connectionState))
                .font(Tokens.body)
                .foregroundStyle(Tokens.muted)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("empty-state-title")

            if EmptyStateCopy.showsActions(session.connectionState) {
                HStack(spacing: 8) {
                    Button("Retry") {
                        Task { await session.retry() }
                    }
                    .font(Tokens.body)
                    .accessibilityIdentifier("empty-state-retry")

                    SettingsLink {
                        Text("Settings")
                            .font(Tokens.body)
                    }
                    .accessibilityIdentifier("empty-state-settings")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.canvas)
    }
}
