import SwiftUI

// §2 #15 StepBar: bars only on compact, bars + names on regular. Reads "Step 3 of 6, Pairing file".

public struct StepBar: View {
    let steps: [LocalizedStringKey], current: Int
    @Environment(\.widthClass) private var width

    public init(steps: [LocalizedStringKey], current: Int) {
        self.steps = steps
        self.current = current
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle()
                        .fill(i < current ? Color.cofre.face : i == current ? Color.cofre.accent : Color.cofre.well)
                        .frame(height: 8)
                        .overlay { Rectangle().stroke(Color.cofre.outline, lineWidth: 2).padding(-1) }
                        .padding(1)
                    if width > .compact {
                        Text(steps[i]).cofreFont(.label).lineLimit(1).minimumScaleFactor(0.8)
                            .foregroundStyle(i == current ? Color.cofre.ink : Color.cofre.muted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(current + 1) of \(steps.count)"))
        .accessibilityValue(steps.indices.contains(current) ? Text(steps[current]) : Text(""))
    }
}
