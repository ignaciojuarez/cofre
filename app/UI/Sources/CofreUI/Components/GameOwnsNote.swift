import SwiftUI

/// Small reminder that the game's files remain the source of truth.
public struct GameOwnsNote: View {
    private let text: LocalizedStringKey

    public init(_ text: LocalizedStringKey) { self.text = text }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.cofre.muted)
            Text(text)
                .cofreFont(.label)
                .foregroundStyle(Color.cofre.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
