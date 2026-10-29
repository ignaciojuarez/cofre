import SwiftUI

// §2 #12 Radio. A row lead; the row carries the selected trait.

public struct Radio: View {
    let isOn: Bool
    public init(isOn: Bool) { self.isOn = isOn }
    public var body: some View {
        Rectangle().fill(Color.cofre.well)
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .overlay {
                if isOn {
                    Rectangle().fill(Color.cofre.accent).frame(width: 6, height: 6)
                        .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 1).padding(-1) }
                }
            }
            .frame(width: 16, height: 16)
            .accessibilityHidden(true)
    }
}
