import SwiftUI

// §2 #19 Stat: value + label, toned. One element: "142, mods".

public struct Stat: View {
    let value: String, label: LocalizedStringKey, tone: Tone
    public init(_ value: String, label: LocalizedStringKey, tone: Tone = .neutral) { self.value = value; self.label = label; self.tone = tone }

    public var body: some View {
        VStack(spacing: 3) {
            Text(verbatim: value).cofreFont(.stat).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(tone == .neutral ? Color.cofre.ink : Color.cofre.tone(tone))
            Text(label).cofreFont(.label).lineLimit(2).multilineTextAlignment(.center).foregroundStyle(Color.cofre.muted)
        }
        .padding(.horizontal, 8).padding(.top, 9).padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .block(.panel)
        .accessibilityElement(children: .combine)
    }
}
