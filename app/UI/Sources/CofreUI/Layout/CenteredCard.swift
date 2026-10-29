import SwiftUI

// §3.2 CenteredCard: full screen on compact; a 560 pt card over a PixelScene on regular (Setup, Ready).

public struct CenteredCard<C: View>: View {
    let width: CGFloat, scene: UInt32, content: C
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(width: CGFloat = 560, scene: UInt32 = 7, @ViewBuilder content: () -> C) {
        self.width = width; self.scene = scene; self.content = content()
    }

    public var body: some View {
        if sizeClass == .compact {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: verticalSizeClass == .compact ? 640 : .infinity)
                    .frame(maxWidth: .infinity)
            }
            .background { PageBackground() }
            .environment(\.widthClass, .compact)
        } else {
            ZStack {
                PixelScene(seed: scene, pixels: .init(width: 240, height: 160)).ignoresSafeArea()
                LinearGradient(colors: [Color.black.opacity(0.15), Color.black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().accessibilityHidden(true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) { content }
                        .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 22)
                        .frame(width: width)
                        .background(BlockBackground(.panel, lip: 4))
                        .shadow(color: .black.opacity(0.6), radius: 40, y: 30)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.center)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 12) {
                    AppIcon(size: 40)
                    Text(verbatim: "Cofre").cofreFont(.title).foregroundStyle(.white).shadow(color: .black, radius: 0, y: 2)
                }
                .padding(.leading, 40).padding(.top, 22)
                .accessibilityHidden(true)
            }
            .environment(\.widthClass, .medium)
        }
    }
}
