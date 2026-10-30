import CofreUI
import SwiftUI

// 8. Game stopped: shorter copy (proposed `GameExitReport` strings), one caption under Close Cofre, and two
// secondary actions instead of three (Copy details moves into Details). Same card, scene and layout as today.

enum GameExitClean {
    struct Copy {
        let explanation: String, nextStep: String
        /// `-exitReason metalReload` or `missingLibrary`.
        static func of(_ reason: String) -> Copy {
            reason == "missingLibrary"
                ? Copy(
                    explanation: "A game file is missing or didn't load.",
                    nextStep: "Play again to recheck the game files. If it happens again, this version may not run on iOS yet.")
                : Copy(
                    explanation: "Metal crashed while reloading graphics.",
                    nextStep: "Your change to Mipmap levels is saved for next time. For now, change graphics and resource packs before joining a world, not in one.")
        }
    }

    struct Preview: View {
        let reason: String
        var body: some View {
            GeometryReader { g in
                let sideBySide = g.size.width >= 600 && g.size.height < 500
                ZStack {
                    PixelScene(seed: 7, pixels: .init(width: 240, height: 160)).ignoresSafeArea()
                    LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                    card(sideBySide: sideBySide)
                        .padding(sideBySide ? 20 : 24)
                        .frame(maxWidth: sideBySide ? 720 : 500)
                        .background(BlockBackground(.panel, lip: 4))
                        .shadow(color: .black.opacity(0.6), radius: 40, y: 24)
                        .padding(.horizontal, 16)
                }
                .environment(\.widthClass, sideBySide || g.size.width >= 700 ? .medium : .compact)
            }
            .preferredColorScheme(.dark)
        }

        @ViewBuilder private func card(sideBySide: Bool) -> some View {
            if sideBySide {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) { message }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) { actions }.frame(width: 250)
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    message
                    VStack(spacing: 8) { actions }.padding(.top, 4)
                }
            }
        }

        @ViewBuilder private var message: some View {
            let copy = Copy.of(reason)
            HStack(spacing: 12) {
                PixelIcon(.head, size: 26).frame(width: 48, height: 48).background(BlockBackground(.tinted(.warn)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minecraft stopped").cofreFont(.title).foregroundStyle(Color.cofre.ink)
                    Text(verbatim: reason == "missingLibrary" ? "Survival+ · Fabric 1.21.1" : "Survival+ · Fabric 26.3")
                        .cofreFont(.label).foregroundStyle(Color.cofre.muted)
                }
            }
            Text(verbatim: copy.explanation).cofreFont(.body).foregroundStyle(Color.cofre.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Next step")
                Text(verbatim: copy.nextStep).cofreFont(.body).foregroundStyle(Color.cofre.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlockBackground(.well))
        }

        @ViewBuilder private var actions: some View {
            BlockButton("Close Cofre", role: .primary, size: .large) {}
            Text("Minecraft runs once per launch. Open Cofre again to play.")
                .cofreFont(.caption).foregroundStyle(Color.cofre.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            HStack(spacing: 8) {
                BlockButton("Share log") {}
                BlockButton("Details") {}
            }
        }
    }
}
