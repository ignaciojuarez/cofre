import CofreUI
import SwiftUI

// 6. Resolution: the pixel size is the only subtitle, a badge only where something is off (no "Sharp" on every row),
// the slider's note only when its size is between presets, and one short line about the in-game setting.

struct ResolutionClean: View {
    @Binding var scale: Double
    let native: RenderResolution

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader("Resolution")
            VStack(alignment: .leading, spacing: 10) {
                ListSection(spacing: 4) {
                    ForEach(native.presets) { preset in
                        let on = native.preset(for: scale) == preset
                        Button {
                            scale = preset.scale
                        } label: {
                            Row(preset.name, subtitle: native.size(preset.scale), isSelected: on) {
                                Radio(isOn: on)
                            } trailing: {
                                if !native.isSharp(preset) { Badge("Uneven", tone: .warn) }
                            }
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
                BlockSlider(
                    "Custom", value: $scale, in: 0.25...1, step: 0.05,
                    note: native.preset(for: scale) == nil ? LocalizedStringKey("Pixels look uneven at this size") : nil
                ) { "\(RenderResolution.percent($0)) · \(native.size($0))" }
                GameOwnsNote("Fullscreen Resolution in game does nothing.")
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
        }
    }

    struct Preview<Real: View>: View {
        let real: Real
        let nav: NavModel
        @State private var scale = 0.7
        var body: some View {
            let native = UserDefaults.standard.string(forKey: "native").flatMap(SceneDelegate.size(from:)).map {
                RenderResolution(width: Int($0.width), height: Int($0.height))
            } ?? RenderResolution(width: Int(UIScreen.main.nativeBounds.width), height: Int(UIScreen.main.nativeBounds.height))
            real
                .task {
                    nav.section = .settings
                    nav.settingsPane = .game
                }
                .reviewSheet { ResolutionClean(scale: $scale, native: native) }
        }
    }
}
