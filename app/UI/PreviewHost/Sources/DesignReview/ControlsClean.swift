import CofreUI
import SwiftUI

// 7. Settings › Controls › Touch: percentages read like the rest of Cofre ("40%", not "40 % of the screen"), and
// Stick area gets one line saying what it is. Rebuilt from public parts; today's pane is `ControlsPane`.

enum ControlsClean {
    struct Preview: View {
        let nav: NavModel
        @Environment(CofreStore.self) private var store
        @State private var settings = TouchControlSettings()
        var body: some View {
            AdaptiveShell(nav: nav) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    ColumnHeader("Controls")
                    PaneScroll {
                        ListSection("Touch", spacing: 4) {
                            BlockSlider("Button size", value: $settings.buttonScale, in: 0.6...1.5, step: 0.05) { percent($0) }
                            BlockSlider("Opacity", value: $settings.opacity, in: 0.2...1, step: 0.05) { percent($0) }
                            BlockSlider(
                                "Stick area", value: $settings.stickArea, in: 0.2...0.6, step: 0.05,
                                note: "Left side of the screen that moves you"
                            ) { percent($0) }
                            BlockSlider("Hold to break", value: $settings.holdToBreak, in: 0.1...0.5, step: 0.05) {
                                "\(Int(($0 * 1000).rounded())) ms"
                            }
                            ToggleRow("Fade when idle", subtitle: "Dims to 35% after 3 s", isOn: $settings.fadeWhenIdle)
                            ToggleRow("Left-handed", subtitle: "Mirror stick and buttons", isOn: $settings.leftHanded)
                            ToggleRow("Haptics", isOn: $settings.haptics)
                            BlockButton("Reset touch controls", role: .ghost) {}
                        }
                    }
                }
                .environment(\.isPushed, true)
            }
            .measuredSizeClasses()
            .task {
                nav.section = .settings
                await store.start()
            }
        }

        private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    }
}
