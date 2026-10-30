#if canImport(UIKit)
    import SwiftUI

    // Settings → Controls (plan/touch-controls.md §4): input mode, touch layout, touch and look options.
    // Touch options live in `TouchControlSettings` (UserDefaults, read live by the game overlay); the input mode
    // goes to the backend; gyro aim stays an Air preference.

    struct ControlsPane: View {
        @Environment(CofreStore.self) private var store
        @State private var settings = TouchControlSettings.load()
        @State private var override = CofreInputMode.auto
        @State private var current = CofreInputMode.touch

        var body: some View {
            let backend = store.services.backend
            ListSection("Input", spacing: 4) {
                Segmented(
                    "Input",
                    selection: Binding(
                        get: { override },
                        set: {
                            override = $0
                            backend.inputModeOverride = $0
                            current = backend.inputMode
                        }),
                    options: [
                        (.auto, "Auto"), (.touch, "Touch"), (.controller, "Controller"),
                        (.keyboardMouse, "Keyboard"),
                    ])
                Text(
                    "Auto switches to a controller or keyboard the moment you use one, and back to touch when you touch the screen."
                )
                .cofreFont(.label).foregroundStyle(Color.cofre.muted).padding(.horizontal, 2)
                Row("Using now", subtitle: Self.title(current)) {
                    PixelIcon(.cmd, size: 20)
                } trailing: {
                    if override == .auto { Badge("Auto", tone: .accent) }
                }
            }
            .task {
                override = backend.inputModeOverride
                for await mode in backend.inputModeUpdates() { current = mode }
            }
            ListSection("Touch layout", spacing: 4) {
                HStack(spacing: 6) {
                    ForEach([TouchLayoutStyle.dock, .classic, .minimal], id: \.self) { style in
                        LayoutTile(style: style, selected: settings.style == style) { settings.style = style }
                    }
                }
            }
            ListSection("Touch", spacing: 4) {
                BlockSlider("Button size", value: $settings.buttonScale, in: 0.6...1.5, step: 0.05) {
                    "\(Int(($0 * 100).rounded())) %"
                }
                BlockSlider("Opacity", value: $settings.opacity, in: 0.2...1, step: 0.05) {
                    "\(Int(($0 * 100).rounded())) %"
                }
                BlockSlider("Stick area", value: $settings.stickArea, in: 0.2...0.6, step: 0.05) {
                    "\(Int(($0 * 100).rounded())) % of the screen"
                }
                BlockSlider("Hold to break", value: $settings.holdToBreak, in: 0.1...0.5, step: 0.05) {
                    "\(Int(($0 * 1000).rounded())) ms"
                }
                ToggleRow("Fade when idle", subtitle: "Dims to 35% after 3 s", isOn: $settings.fadeWhenIdle)
                ToggleRow("Left-handed", subtitle: "Mirror stick and buttons", isOn: $settings.leftHanded)
                ToggleRow("Haptics", isOn: $settings.haptics)
                BlockButton("Reset touch controls", role: .ghost) {
                    var fresh = TouchControlSettings()
                    fresh.lookSensitivity = settings.lookSensitivity
                    fresh.invertY = settings.invertY
                    settings = fresh
                }
            }
            ListSection("Look", spacing: 4) {
                BlockSlider("Look sensitivity", value: $settings.lookSensitivity, in: 0.25...3, step: 0.05) {
                    String(format: "%.2f×", $0)
                }
                ToggleRow("Invert Y", isOn: $settings.invertY)
                ToggleRow(
                    "Gyro aim", subtitle: "Fine-tune aim by tilting",
                    isOn: Binding(
                        get: { store.preferences.gyroAim },
                        set: {
                            var p = store.preferences
                            p.gyroAim = $0
                            store.save(p)
                        }))
            }
            .onChange(of: settings) { _, new in new.save() }
        }

        static func title(_ mode: CofreInputMode) -> LocalizedStringKey {
            switch mode {
            case .auto, .touch: "Touch"
            case .controller: "Controller"
            case .keyboardMouse: "Keyboard & mouse"
            }
        }
    }

    /// A live mini render of the overlay in that style, over the stand-in game.
    private struct LayoutTile: View {
        let style: TouchLayoutStyle, selected: Bool
        let pick: () -> Void

        var body: some View {
            Button(action: pick) {
                VStack(spacing: 6) {
                    // Rendered at iPhone landscape size, then scaled to the tile so three fit in portrait too.
                    Color.clear
                        .aspectRatio(874 / 402, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            GeometryReader { g in
                                TouchOverlayPreview(style: style, state: style == .minimal ? .active : .rest)
                                    .frame(width: 874, height: 402)
                                    .scaleEffect(g.size.width / 874, anchor: .topLeading)
                            }
                        }
                        .clipped()
                        .allowsHitTesting(false)
                    Text(verbatim: style.title).cofreFont(.chip).foregroundStyle(Color.cofre.ink)
                }
                .padding(6)
                .frame(maxWidth: .infinity)
                .block(.panel, selected: selected)
                .overlay { if selected { Rectangle().strokeBorder(Color.cofre.accent, lineWidth: 2) } }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: style.title))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
#endif
