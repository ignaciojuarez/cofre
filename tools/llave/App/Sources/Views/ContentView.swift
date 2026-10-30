import AppKit
import CofreUI
import SwiftUI

/// The helper's one window, in Cofre's look: the pixel stage on top, then what to do now.
/// It moves on by itself; a button shows only when you have to act. Return runs it, Esc closes.
public struct ContentView: View {
    @ObservedObject public var model: LlaveModel
    @Environment(\.openURL) private var openURL
    /// Feedback after AirDrop or Save, shown in place of the help line.
    @State private var note: String? = PreviewState.note

    /// Hidden title bar; the stage runs up under it so the window is 620 pt tall overall.
    private static let titleBar: CGFloat = 32
    /// Step 1 of the setup site (GitHub Pages from `docs/`). Keep in sync with `docs/app.js` LINKS.
    private static let getCofre = URL(string: "https://ignaciojuarez.github.io/cofre/#step-1")!

    public init(model: LlaveModel) {
        self.model = model
    }

    private var state: LlaveState { PreviewState.current ?? model.state }

    public var body: some View {
        let screen = StateScreen(state)
        VStack(spacing: 0) {
            PairingStage(art: screen.art)
                .overlay(alignment: .bottom) { Color.cofre.outline.frame(height: 2) }
                .frame(height: PairingStage.size.height - Self.titleBar, alignment: .bottom)
                .accessibilityElement()
                .accessibilityLabel(screen.artLabel)
                .accessibilityAddTraits(.isImage)
            VStack(alignment: .leading, spacing: 10) {
                Text("Step 3 · Connect to a Mac").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                Text(screen.title).cofreFont(.title).foregroundStyle(Color.cofre.ink).accessibilityAddTraits(.isHeader)
                Text(note ?? screen.help).cofreFont(.secondary).foregroundStyle(Color.cofre.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let step = screen.step {
                    StepBar(steps: StateScreen.steps.map { LocalizedStringKey($0) }, current: step)
                        .padding(.top, 8)
                        .accessibilityHidden(step >= StateScreen.steps.count)
                }
                if !screen.devices.isEmpty { devicePicker(screen.devices) }
                if screen.keyOnMac {
                    Banner("Never share this file. It's a key to your iPhone.", icon: .shield, tone: .warn)
                }
                Spacer(minLength: 0)
                actions(screen)
                footer
            }
            .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 12)
            .animation(.linear(duration: CofreTheme.standard.motion.reducedCrossfade), value: screen.title)
        }
        .frame(width: 520, height: 620 - Self.titleBar)
        .background { PageBackground() }
        .environment(\.widthClass, .medium)
        .preferredColorScheme(.dark)
        .tint(Color.cofre.accent)
        .background {
            // Esc closes, except mid-transfer: the key is on its way into Cofre.
            Button("Close") { if !isTransferring { close() } }.keyboardShortcut(.cancelAction)
                .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .onChange(of: screen.title) { _, title in
            note = nil
            AccessibilityNotification.Announcement(title).post()
        }
    }

    private func devicePicker(_ devices: [Device]) -> some View {
        VStack(spacing: 5) {
            ForEach(devices) { device in
                Button { model.startPairing(device: device) } label: {
                    Row(device.name, subtitle: "iOS \(device.version)", leading: { PixelIcon(.head, size: 20) }, trailing: { Chevron() })
                }
                .buttonStyle(RowButtonStyle())
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private func actions(_ screen: StateScreen) -> some View {
        if let waiting = screen.waiting {
            Row(waiting, leading: { Spinner() }, trailing: { Meta("Auto") })
        }
        if let primary = screen.primary {
            BlockButton(primary.title, icon: primary.icon, role: .primary, size: .large) { run(primary) }
                .keyboardShortcut(.defaultAction)
        }
        if let secondary = screen.secondary {
            if case .saveToDesktop = secondary {
                // Last resort: a copy on the Desktop is a key to the iPhone, so it's small and says to delete it.
                BlockButton(secondary.title, role: .ghost, size: .small) { run(secondary) }
            } else {
                BlockButton(secondary.title, icon: secondary.icon) { run(secondary) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PixelIcon(.shield, size: 14)
            Text("Nothing is uploaded. Nothing stays on this Mac unless you save it.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !isTransferring { KeyHint("esc", "Close") }
        }
        .padding(.top, 2)
    }

    private func run(_ action: StateScreen.Action) {
        switch action {
        case .close: close()
        case .getCofre: openURL(Self.getCofre)
        case .tryAgain: model.reset()
        case .airDrop:
            note = model.sendViaAirDrop() ? StateScreen.airDropSent : StateScreen.airDropMissing
        case .saveToDesktop:
            note = model.saveToDesktop() != nil ? StateScreen.saved : StateScreen.saveFailed
        }
    }

    private var isTransferring: Bool {
        switch state { case .pairing, .placing: true; default: false }
    }

    private func close() { NSApp.terminate(nil) }
}
