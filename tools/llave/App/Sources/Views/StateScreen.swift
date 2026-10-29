import CofreUI
import Foundation

/// What the window shows for one `LlaveState`: art, a title, one line of help, and buttons only when you must act.
/// Copy matches Step 3 on the site and PAIRING.md. No jargon, and the raw error text never reaches the window.
struct StateScreen {
    enum Art: Equatable { case plugIn, pick(Int), unlock, trust, connecting, placing, done, missing, airDrop, problem }

    enum Action {
        case close, getCofre, tryAgain, airDrop, saveToDesktop

        var title: String {
            switch self {
            case .close: "Close"
            case .getCofre: "How to get Cofre"
            case .tryAgain: "Try again"
            case .airDrop: "Send with AirDrop"
            case .saveToDesktop: "Save to Desktop"
            }
        }

        var icon: PixelGlyph? {
            switch self {
            case .getCofre: .chest
            case .airDrop: .key
            case .saveToDesktop: .paper
            case .close, .tryAgain: nil
            }
        }
    }

    /// The three checks from the site's "What you'll see".
    static let steps: [String] = ["iPhone connected", "Trusted", "Key sent to Cofre"]

    var art: Art
    var title: String
    var help: String
    /// Position in `steps`; `steps.count` means all done, nil hides the bar.
    var step: Int?
    /// Shown with a Spinner where the button would be, while the window moves on by itself.
    var waiting: String?
    var devices: [Device] = []
    var primary: Action?
    var secondary: Action?

    init(_ state: LlaveState) {
        switch state {
        case .noDevice:
            self.init(.plugIn, "Plug in your iPhone", "Use a cable that carries data, not just charging.", step: 0)
            waiting = "Looking for your iPhone\u{2026}"
        case .multipleDevices(let devices):
            self.init(.pick(devices.count), "Pick your iPhone", "More than one iPhone is plugged in. Which one gets the key?")
            self.devices = devices
        case .locked(let device):
            self.init(.unlock, "Unlock your iPhone", "Unlock \(device.name) and keep it on.", step: 1)
            waiting = "Waiting for unlock\u{2026}"
        case .waitingForTrust:
            self.init(.trust, "Tap \u{201C}Trust\u{201D} on your iPhone", "Then enter your iPhone passcode.", step: 1)
            waiting = "Waiting for Trust\u{2026}"
        case .pairing:
            self.init(.connecting, "Connecting to your iPhone\u{2026}", "Keep it unlocked and plugged in.", step: 1)
            waiting = "Talking to your iPhone\u{2026}"
        case .placing:
            self.init(.placing, "Putting your key inside Cofre\u{2026}", "Keep your iPhone unlocked and plugged in.", step: 2)
            waiting = "Sending the key\u{2026}"
        case .done:
            self.init(.done, "Done", "Open Cofre on your iPhone. It's ready.", step: Self.steps.count, primary: .close)
        case .cofreMissing(let device):
            self.init(.missing, "Install Cofre first", "Cofre isn't on \(device.name) yet. Install it, then try again.",
                      primary: .getCofre, secondary: .tryAgain)
        case .error(let error) where error.code == "COFRE_MISSING":
            self.init(.missing, "Install Cofre first", "Install Cofre on your iPhone, then try again.", primary: .getCofre, secondary: .tryAgain)
        case .placementFailed:
            self.init(.airDrop, "Send it with AirDrop instead", "The key couldn't go in over the cable. AirDrop works too.",
                      primary: .airDrop, secondary: .saveToDesktop)
        case .ready:
            self.init(.airDrop, "Your key is ready", "Send it to your iPhone with AirDrop.", primary: .airDrop, secondary: .saveToDesktop)
        case .error(let error):
            let (title, help) = Self.problem(error.code)
            self.init(.problem, title, help, primary: error.code == "CLI_NOT_FOUND" ? .close : .tryAgain)
        }
    }

    private init(_ art: Art, _ title: String, _ help: String, step: Int? = nil, primary: Action? = nil, secondary: Action? = nil) {
        self.art = art; self.title = title; self.help = help; self.step = step; self.primary = primary; self.secondary = secondary
    }

    /// Friendly copy per error code. Unknown codes get the generic line.
    private static func problem(_ code: String) -> (String, String) {
        switch code {
        case "USER_DENIED": ("You tapped Don't Trust", "Unplug your iPhone, plug it back in, then tap Trust.")
        case "PASSWORD_PROTECTED": ("Unlock your iPhone", "Unlock it and keep it on, then try again.")
        case "NO_DEVICE": ("Can't find your iPhone", "Use a cable that carries data, then try again.")
        case "DEVICE_RESTRICTED": ("This iPhone can't connect", "It may be managed by a school or company.")
        case "VALIDATION_FAILED": ("The key didn't work", "Unplug your iPhone, plug it back in, then try again.")
        case "PLACEMENT_FAILED": ("The key didn't go in", "Keep Cofre installed and your iPhone unlocked, then try again.")
        case "CLI_NOT_FOUND": ("Part of this helper is missing", "Close this window and run the Terminal command again.")
        case "SAVE_FAILED": ("Couldn't save the file", "Check your Mac has free space, then try again.")
        default: ("Something went wrong", "Unplug your iPhone, plug it back in, then try again.")
        }
    }

    /// VoiceOver description of the art.
    var artLabel: String {
        switch art {
        case .plugIn: "A Mac and an iPhone. The cable isn't plugged in yet."
        case .pick(let n): "A Mac with \(n) iPhones plugged in."
        case .unlock: "An iPhone plugged into a Mac, showing its lock screen."
        case .trust: "An iPhone plugged into a Mac, asking: Trust This Computer?"
        case .connecting: "A Mac talking to an iPhone over the cable."
        case .placing: "A key moving over the cable into Cofre on the iPhone."
        case .done: "Cofre on the iPhone, with a check mark."
        case .missing: "An iPhone without Cofre."
        case .airDrop: "A Mac sending the key to an iPhone with AirDrop."
        case .problem: "An iPhone plugged into a Mac, with a red cross."
        }
    }
}
