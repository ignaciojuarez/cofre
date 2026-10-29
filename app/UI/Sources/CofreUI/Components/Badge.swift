import SwiftUI

// §2 #3 Badge. Read as part of its row; never the only signal of state.

public struct Badge: View {
    let text: Text, tone: Tone, big: Bool

    public init(_ text: LocalizedStringKey, tone: Tone = .neutral, big: Bool = false) {
        self.text = Text(text); self.tone = tone; self.big = big
    }

    @_disfavoredOverload
    public init(_ text: String, tone: Tone = .neutral, big: Bool = false) {
        self.text = Text(verbatim: text); self.tone = tone; self.big = big
    }

    public var body: some View {
        text
            .cofreFont(big ? .buttonS : .badge)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tone == .neutral ? Color.cofre.inkSoft : Color.cofre.ink)
            .padding(.horizontal, big ? 9 : 6)
            .padding(.bottom, 1)
            .frame(minHeight: big ? 26 : 19)
            .background(tone == .neutral ? Color.cofre.well : Color.cofre.tint(tone))
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
    }
}

public extension Badge {
    /// Loader badge ("Fabric 1.21.1") with the loader's tone.
    init(loader: Loader, version: String? = nil) {
        self.init([loader.displayName, version].compactMap { $0 }.joined(separator: " "), tone: loader.tone)
    }
}
