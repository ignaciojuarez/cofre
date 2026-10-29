import SwiftUI

public struct ContentView: View {
    @ObservedObject public var model: LlaveModel

    public init(model: LlaveModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 16) {
            Toggle("Simulate Mode", isOn: $model.isSimulating)

            Divider()

            switch model.state {
            case .noDevice:
                Text("No device connected")
                Text("Connect your iPhone via USB")
                    .foregroundColor(.secondary)

            case .multipleDevices(let devices):
                Text("Multiple devices found:")
                ForEach(devices) { dev in
                    Button("Pair \(dev.name) (\(dev.udid.prefix(8))...)") {
                        model.startPairing(device: dev)
                    }
                }

            case .locked(let dev):
                Text("iPhone is Locked")
                Text("Please unlock \(dev.name) to continue")
                    .foregroundColor(.secondary)

            case .waitingForTrust(let dev):
                Text("Trust This Computer")
                Text("Please tap 'Trust' and enter your passcode on \(dev.name)")
                    .foregroundColor(.secondary)

            case .pairing(let dev):
                Text("Pairing with \(dev.name)...")
                ProgressView()

            case .placing(let dev):
                Text("Putting your key inside Cofre…"); ProgressView()

            case .done:
                Text("✓ Done, open Cofre")

            case .cofreMissing:
                Text("Install Cofre first")
                Link("Get Cofre", destination: URL(string: "https://github.com/ignaciojuarez/cofre")!)

            case .placementFailed:
                Text("Cofre placement failed")
                HStack { Button("Send with AirDrop") { _ = model.sendViaAirDrop() }; Button("Save to Desktop") { _ = model.saveToDesktop() } }

            case .ready(let fileURL):
                Text("Pairing File Ready")
                Text(fileURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("AirDrop to iPhone") {
                        _ = model.sendViaAirDrop()
                    }
                    Button("Save to Desktop") {
                        _ = model.saveToDesktop()
                    }
                }

            case .error(let error):
                Text("Error")
                    .foregroundColor(.red)
                Text(error.friendlyCopy)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    model.reset()
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 320, minHeight: 240)
    }
}
