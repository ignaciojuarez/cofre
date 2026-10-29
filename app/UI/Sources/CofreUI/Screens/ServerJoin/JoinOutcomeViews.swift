#if canImport(UIKit)
import SwiftUI

// Resolving, error and ready. Same blocks as the mockup's four states.

struct JoinResolvingBody: View {
    var body: some View {
        Row("Reading the server's pack…", leading: { Spinner() }, trailing: { Meta("Checking") })
        NoteText("Cofre checks the server's signature before it shows what to install.", color: Color.cofre.muted)
    }
}

// MARK: - Error

/// What the sheet says for each code. The backend's `title` and `message` never show, so raw errors can't leak.
struct JoinErrorCopy: Equatable {
    let title: String, message: String

    init(_ code: ServerJoinErrorState.ErrorCode) {
        switch code {
        case .networkTimeout:
            title = String(localized: "Can't reach the server")
            message = String(localized: "The connection timed out. Check your internet, then try again.")
        case .hostNotFound:
            title = String(localized: "Server not found")
            message = String(localized: "Check the address, or ask the server owner if it moved.")
        case .checksumMismatch:
            title = String(localized: "A download didn't check out")
            message = String(localized: "A file didn't match what the server signed, so Cofre didn't use it. Try again.")
        case .storageFull:
            title = String(localized: "Not enough space")
            message = String(localized: "Free up some space, then try again. Nothing was changed.")
        case .jitMissing:
            title = String(localized: "JIT is off")
            message = String(localized: "Cofre needs JIT to run the game. Turn it on, then join again.")
        case .signatureRejected:
            title = String(localized: "This pack isn't signed correctly")
            message = String(localized: "Cofre stopped and installed nothing. Tell the server owner.")
        case .pathTraversalDetected:
            title = String(localized: "This pack tried something unsafe")
            message = String(localized: "It tried to put files outside its folder. Cofre stopped and installed nothing. Tell the server owner.")
        case .curseForgeRestricted:
            title = String(localized: "Download a mod yourself")
            message = String(localized: "Its author only allows downloads from CurseForge. Open it, tap Download, and Cofre picks it up.")
        }
    }
}

extension RecoveryAction {
    var buttonTitle: LocalizedStringKey {
        switch self {
        case .retry: "Try again"
        case .openSettingsStorage: "Free up space"
        case .triggerJITWorkflow: "Turn on JIT"
        case .openCurseForgeWeb: "Open CurseForge \(joinArrow)"
        case .contactServerAdmin, .dismiss: "Close"
        }
    }
}

struct JoinErrorBody: View {
    let error: ServerJoinErrorState
    var body: some View {
        let copy = JoinErrorCopy(error.code)
        Banner(copy.title, icon: .cross, tone: .danger)
        NoteText(verbatim: copy.message)
    }
}

struct JoinErrorFooter: View {
    let error: ServerJoinErrorState
    let send: (ServerJoinAction) -> Void
    @Environment(NavModel.self) var nav: NavModel?
    @JoinDismiss var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        JoinPrimaryButton(title: error.recoveryAction.buttonTitle, action: recover)
    }

    private func recover() {
        switch error.recoveryAction {
        case .retry: send(.retry)
        case .openSettingsStorage: dismiss(); nav?.section = .settings; nav?.settingsPane = .accounts
        case .triggerJITWorkflow: dismiss(); nav?.section = .settings; nav?.settingsPane = .jitJava
        case .openCurseForgeWeb(let url, _): if url.scheme?.lowercased() == "https" { openURL(url) }
        case .contactServerAdmin, .dismiss: dismiss()
        }
    }
}

// MARK: - Ready

struct JoinReadyBody: View {
    let ready: ServerJoinReadyState
    let send: (ServerJoinAction) -> Void
    @Environment(NavModel.self) var nav: NavModel?
    @JoinDismiss var dismiss

    var body: some View {
        Banner("Installed and checked. Ready to join.", icon: .check, tone: .success)
        ToggleRow("Join this server when the game starts", subtitle: ready.serverAddress,
                  isOn: Binding(get: { ready.autoConnectOnLaunch }, set: { send(.setAutoConnect($0)) }))
        if !ready.isJITReady {
            Banner("JIT is off. Turn it on to play.", icon: .bolt, tone: .warn) {
                BlockButton("Turn on", size: .small) { dismiss(); nav?.section = .settings; nav?.settingsPane = .jitJava }
            }
        }
    }
}

struct JoinReadyFooter: View {
    let ready: ServerJoinReadyState
    let send: (ServerJoinAction) -> Void
    @Environment(CofreStore.self) var store: CofreStore?
    @JoinDismiss var dismiss

    var body: some View {
        JoinPrimaryButton(title: LocalizedStringKey(ready.primaryButtonTitle), enabled: ready.isJITReady) {
            send(.launch)
            // The root starts the launch takeover once this sheet is gone.
            store?.pendingJoinLaunch = ready.instanceID
            dismiss()
        }
    }
}
#endif
