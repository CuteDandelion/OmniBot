import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Create an agent to start.")
                .font(Tokens.body)
                .foregroundStyle(Tokens.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.canvas)
    }
}
