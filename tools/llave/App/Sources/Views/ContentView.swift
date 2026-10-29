import AppKit
import CofreUI
import SwiftUI

/// The helper's one window, in Cofre's look: the pixel stage on top, then what to do now.
/// It moves on by itself; a button shows only when you have to act. Return runs it, Esc closes.
public struct ContentView: View {
    @ObservedObject public var model: LlaveModel
    @Environment(\.openURL) private var openURL
    /// Feedback after AirDrop or Save, shown in place of the help line.
    @State private var note: String?

    /// Hidden title bar; the stage runs up under it so the window is 620 pt tall overall.
    private static let titleBar: CGFloat = 32
    /// Step 1 of the setup (README). Keep in sync with `docs/app.js` LINKS.
    private static let getCofre = URL(string: "https://github.com/ignaciojuarez/cofre#readme")!

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
                Spacer(minLength: 0)
                actions(screen)
                footer
            }
            .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 18)
            .animation(.linear(duration: CofreTheme.standard.motion.reducedCrossfade), value: screen.title)
        }
        .frame(width: 520, height: 620 - Self.titleBar)
        .background { PageBackground() }
        .environment(\.widthClass, .medium)
        .preferredColorScheme(CofreTheme.standard.colorScheme)
        .tint(Color.cofre.accent)
        .background {
            Button("Close", action: close).keyboardShortcut(.cancelAction)
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
            BlockButton(secondary.title, icon: secondary.icon) { run(secondary) }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PixelIcon(.shield, size: 14)
            Text("Nothing is uploaded").cofreFont(.label).foregroundStyle(Color.cofre.muted)
            Spacer()
            KeyHint("esc", "Close")
        }
        .padding(.top, 6)
    }

    private func run(_ action: StateScreen.Action) {
        switch action {
        case .close: close()
        case .getCofre: openURL(Self.getCofre)
        case .tryAgain: model.reset()
        case .airDrop:
            note = model.sendViaAirDrop()
                ? "Pick your iPhone, then tap Accept on it. In Cofre, tap I have a file."
                : "AirDrop isn't available here. Save to Desktop instead."
        case .saveToDesktop:
            note = model.saveToDesktop() != nil
                ? "Saved to your Desktop. Send it to your iPhone with AirDrop."
                : "Couldn't save the file. Try AirDrop instead."
        }
    }

    private func close() { NSApp.terminate(nil) }
}
