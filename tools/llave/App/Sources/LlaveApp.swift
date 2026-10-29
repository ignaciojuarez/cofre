import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: LlaveModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["LLAVE_SIMULATE"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) } }
    }

    /// One window; closing it ends the helper so `pair.sh` can finish.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model?.cleanupTemporaryFile()
    }
}

@main
struct LlaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // A preview run never talks to a real iPhone.
    @StateObject private var model = LlaveModel(isSimulating: ProcessInfo.processInfo.environment["LLAVE_SIMULATE"] == "1" || PreviewState.current != nil)

    var body: some Scene {
        Window("Cofre", id: "llave") {
            ContentView(model: model)
                .onAppear {
                    appDelegate.model = model
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
