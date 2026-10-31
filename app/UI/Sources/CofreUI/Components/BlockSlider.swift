import SwiftUI

// §2 #8 Slider. Value text on the right, optional range note and default tick. Adjustable for VoiceOver.

public struct BlockSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>, step: Double
    let valueText: (Double) -> String
    let accessibilityText: ((Double) -> String)?
    let note: LocalizedStringKey?
    let defaultValue: Double?

    public init(
        _ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1,
        note: LocalizedStringKey? = nil, defaultValue: Double? = nil, accessibilityValue: ((Double) -> String)? = nil,
        valueText: @escaping (Double) -> String
    ) {
        self.title = title
        _value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.note = note
        self.defaultValue = defaultValue
        self.accessibilityText = accessibilityValue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                Spacer(minLength: 8)
                Text(verbatim: valueText(value)).cofreFont(.label).foregroundStyle(Color.cofre.inkSoft)
            }
            SliderTrack(value: $value, range: range, step: step, defaultValue: defaultValue).frame(height: 44)
            if let note { Text(note).cofreFont(.label).foregroundStyle(Color.cofre.muted) }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
        .block(.panel)
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(title) }
                .accessibilityValue(Text(verbatim: (accessibilityText ?? valueText)(value)))
                .accessibilityHint(defaultValue.map { "Default " + (accessibilityText ?? valueText)($0) } ?? "")
        }
    }
}

private struct SliderTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>, step: Double
    let defaultValue: Double?

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = (w - 14) * fraction(value)
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.cofre.well)
                    .overlay(alignment: .leading) { Color.cofre.face.frame(width: max(0, x + 7)) }
                    .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                    .frame(height: 12)
                if let defaultValue {
                    // Default tick under the track; the thumb sits on it at the default.
                    Color.cofre.outline.frame(width: 2, height: 8)
                        .offset(x: (w - 14) * fraction(defaultValue) + 6, y: 13)
                }
                Rectangle().fill(Color.white)
                    .overlay(alignment: .bottom) { Color(white: 0.79).frame(height: 3) }
                    .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                    .frame(width: 14, height: 22)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { d in
                    let p = min(max(0, (d.location.x - 7) / max(1, w - 14)), 1)
                    let raw = range.lowerBound + p * (range.upperBound - range.lowerBound)
                    value = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                })
        }
        .blockPointer()
    }

    private func fraction(_ v: Double) -> Double { min(max((v - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1) }
}
