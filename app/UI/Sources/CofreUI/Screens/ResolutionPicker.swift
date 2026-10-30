#if canImport(UIKit)
    import SwiftUI
    import UIKit

    extension EnvironmentValues {
        /// Previews only: size the presets for this screen instead of the window's.
        @Entry public var screenPixels: RenderResolution? = nil
        /// Previews only: open the Resolution picker on appear.
        @Entry public var opensResolutionPicker = false
    }

    extension RenderResolution {
        /// This window's screen in native pixels.
        @MainActor static var screen: RenderResolution {
            let size =
                UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first?.nativeBounds.size
                ?? .zero
            return RenderResolution(width: Int(size.width), height: Int(size.height))
        }
    }

    /// Settings row: the current choice and its real pixel size ("Balanced · 1133 × 744"). Opens the picker.
    struct ResolutionRow: View {
        @Binding var scale: Double
        @Environment(\.screenPixels) private var screenPixels
        @Environment(\.opensResolutionPicker) private var opens
        @State private var showing = false

        var body: some View {
            let native = screenPixels ?? .screen
            Button {
                showing = true
            } label: {
                ValueRow("Resolution", value: native.label(scale))
            }
            .buttonStyle(RowButtonStyle())
            .onAppear { if opens { showing = true } }
            .blockSheet(isPresented: $showing, hugsContent: true) { ResolutionPicker(scale: $scale, native: native) }
        }
    }

    struct ResolutionPicker: View {
        @Binding var scale: Double
        let native: RenderResolution
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                SheetHeader("Resolution")
                VStack(alignment: .leading, spacing: 10) {
                    ListSection(spacing: 4) {
                        ForEach(native.presets) { preset in
                            let on = native.preset(for: scale) == preset
                            Button {
                                scale = preset.scale
                                dismiss()
                            } label: {
                                Row(
                                    preset.name,
                                    subtitle: "\(native.size(preset.scale)) · \(RenderResolution.share(preset.scale)) of pixels",
                                    isSelected: on
                                ) {
                                    Radio(isOn: on)
                                } trailing: {
                                    if native.isSharp(preset) { Badge("Sharp", tone: .success) }
                                }
                            }
                            .buttonStyle(RowButtonStyle())
                        }
                    }
                    BlockSlider(
                        "Custom", value: $scale, in: 0.25...1, step: 0.05,
                        note: "Sizes between the presets may look uneven.",
                        accessibilityValue: { "\(RenderResolution.percent($0)), \(native.size($0))" }
                    ) { "\(RenderResolution.percent($0)) · \(native.size($0))" }
                    Text("Minecraft's Fullscreen Resolution setting does nothing on iPhone and iPad; this sets the real size.")
                        .cofreFont(.caption).foregroundStyle(Color.cofre.muted).padding(.horizontal, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            }
        }
    }
#endif
