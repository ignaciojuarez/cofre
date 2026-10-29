import SwiftUI

// §2 #13 ProgressBar. XP style: fills in 9 pt segments with no tween. Indeterminate shows Spinner + text.

public struct XPProgressStyle: ProgressViewStyle {
    let tone: Tone, small: Bool
    public init(tone: Tone = .success, small: Bool = false) {
        self.tone = tone
        self.small = small
    }

    public func makeBody(configuration: Configuration) -> some View {
        Group {
            if let f = configuration.fractionCompleted {
                XPBar(fraction: f, tone: tone, small: small)
                    .accessibilityElement()
                    .accessibilityValue(Text("\(Int((f * 100).rounded())) percent"))
            } else {
                HStack(spacing: 8) {
                    Spinner()
                    configuration.label.cofreFont(.label).foregroundStyle(Color.cofre.muted)
                }
            }
        }
    }
}

extension ProgressViewStyle where Self == XPProgressStyle {
    public static func xp(_ tone: Tone = .success, small: Bool = false) -> Self { .init(tone: tone, small: small) }
}

struct XPBar: View {
    let fraction: Double, tone: Tone, small: Bool
    var body: some View {
        let color = tone == .neutral ? Color.cofre.inkSoft : Color.cofre.tone(tone)
        GeometryReader { g in
            let inner = g.size.width - 8
            let seg: CGFloat = 11
            let count = Int((inner * min(max(fraction, 0), 1)) / seg)
            HStack(spacing: 2) {
                ForEach(0..<max(count, 0), id: \.self) { _ in Rectangle().fill(color).frame(width: 9) }
            }
            .frame(height: small ? 4 : 8)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: small ? 12 : 16)
        .background(Color.cofre.well)
        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
        .transaction { $0.animation = nil }
    }
}
