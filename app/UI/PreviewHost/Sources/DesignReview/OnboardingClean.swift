import CofreUI
import SwiftUI

// 9. Onboarding on regular width (iPad, big iPhones in landscape): the card on Cofre's page texture, like every
// other screen. The lake behind it scaled the 240 × 160 scene up to fill the window, so in iPad portrait the moon
// became a ~200 pt block, and it repeated the scene that already heads the Welcome card. One moon, in the card.
// The corner logo goes too: the card's header already shows it, and in iPhone landscape the two overlapped.
// `CenteredCard`'s regular branch with `PageBackground()` in place of `PixelScene` and its gradient, no corner logo.

enum OnboardingClean {
    struct Preview: View {
        var body: some View { Welcome().measuredSizeClasses() }
    }

    private struct Welcome: View {
        @Environment(\.horizontalSizeClass) private var sizeClass
        var body: some View {
            if sizeClass == .compact {
                // Compact already uses the page texture; nothing changes there.
                ScrollView { welcome.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24).frame(maxWidth: 640) }
                    .frame(maxWidth: .infinity)
                    .background { PageBackground() }
                    .environment(\.widthClass, .compact)
            } else {
                ScrollView {
                    welcome
                        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 22)
                        .frame(width: 560)
                        .background(BlockBackground(.panel, lip: 4))
                        .shadow(color: .black.opacity(0.6), radius: 40, y: 30)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center)
                .background { PageBackground().ignoresSafeArea() }
                .environment(\.widthClass, .medium)
            }
        }

        private var welcome: some View {
            VStack(alignment: .leading, spacing: 14) {
                PixelScene(seed: 11, pixels: .init(width: 240, height: 84))
                    .frame(height: 150).frame(minWidth: 0, maxWidth: .infinity).clipped()
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 10) {
                            AppIcon(size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: "Cofre").cofreFont(.title2).foregroundStyle(.white)
                                Text("Java Edition").cofreFont(.label).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .shadow(color: .black, radius: 0, y: 2)
                        .padding(12)
                    }
                    .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                Text("Java Edition. In your pocket.").cofreFont(.display).foregroundStyle(Color.cofre.ink)
                Text("Mods, packs, shaders. All on this device.").cofreFont(.body).foregroundStyle(Color.cofre.muted)
                AdaptiveGrid(minItem: 90, maxColumns: 3) {
                    Stat("4", label: "Steps")
                    Stat("10", label: "Minutes")
                    Stat("1×", label: "Mac visit")
                }
                BlockButton("Set up", role: .primary, size: .large) {}
                Text("Unofficial. Not from Mojang or Microsoft.").cofreFont(.label).foregroundStyle(Color.cofre.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
