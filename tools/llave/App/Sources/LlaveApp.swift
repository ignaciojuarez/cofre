import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: LlaveModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["LLAVE_SIMULATE"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) } }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.cleanupTemporaryFile()
    }
}

@main
struct LlaveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = LlaveModel(isSimulating: ProcessInfo.processInfo.environment["LLAVE_SIMULATE"] == "1")

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear {
                    appDelegate.model = model
                }
        }
    }
}
