import SwiftUI

// §2 #14 Spinner: four pixels blinking in turn, 1 s steps. Static under Reduce Motion. Hidden from VoiceOver.

public struct Spinner: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(size: CGFloat = 14) { self.size = size }

    public var body: some View {
        Group {
            if reduceMotion {
                cells(phase: -1)
            } else {
                TimelineView(.periodic(from: .now, by: 0.25)) { ctx in cells(phase: Int(ctx.date.timeIntervalSinceReferenceDate * 4) % 4) }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func cells(phase: Int) -> some View {
        let order = [0, 1, 3, 2] // clockwise
        let cell = (size - 2) / 2
        return VStack(spacing: 2) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: 2) {
                    ForEach(0..<2, id: \.self) { c in
                        Rectangle().fill(Color.cofre.accent)
                            .frame(width: cell, height: cell)
                            .opacity(phase >= 0 && order[phase] == r * 2 + c ? 0.2 : 1)
                    }
                }
            }
        }
    }
}
