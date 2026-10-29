import SwiftUI

// §2 #27 NavChrome: one NAV list rendered as tab bar (compact), 76 pt rail (medium) or 248 pt sidebar (expanded).

public struct NavChrome: View {
    public enum Style: Sendable { case tabBar, rail, sidebar }
    let style: Style
    @Bindable var nav: NavModel
    @Environment(CofreStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.cofreTheme) private var theme

    public init(style: Style, nav: NavModel) { self.style = style; self.nav = nav }

    public var body: some View {
        switch style {
        case .tabBar: tabBar
        case .rail: rail
        case .sidebar: sidebar
        }
    }

    private func select(_ s: NavModel.Section) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: theme.motion.select)) { nav.section = s }
    }

    private func badge(for s: NavModel.Section) -> Int { s == .mods ? store.updateCount : 0 }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(NavModel.Section.allCases, id: \.self) { s in
                let on = nav.section == s
                Button { select(s) } label: {
                    VStack(spacing: 5) {
                        PixelIcon(s.glyph, size: 18).opacity(on ? 1 : 0.55).foregroundStyle(on ? Color.cofre.ink : Color.cofre.muted)
                        Text(s.title).cofreFont(.navSmall).lineLimit(1)
                    }
                    .foregroundStyle(on ? Color.cofre.ink : Color.cofre.muted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(on ? Color.cofre.raised : Color.clear)
                    .overlay(alignment: .top) { if on { Color.cofre.accent.frame(height: theme.block.tabSelectionBar) } }
                    .overlay(alignment: .topTrailing) { countBadge(badge(for: s)).padding(6) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(s.shortcut, modifiers: .command)
                .accessibilityShowsLargeContentViewer { PixelIcon(s.glyph, size: 18); Text(s.title) }
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .accessibilityValue(badge(for: s) > 0 ? Text("\(badge(for: s)) updates") : Text(""))
                .blockPointer()
            }
        }
        .background(Color.cofre.side.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Color.cofre.outline.frame(height: 2) }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(spacing: 3) {
            AppIcon(size: 34).padding(.top, 6).padding(.bottom, 12)
            ForEach(NavModel.Section.allCases, id: \.self) { s in
                navButton(s) { on in
                    VStack(spacing: 6) {
                        PixelIcon(s.glyph, size: 22).opacity(on ? 1 : 0.55)
                        Text(s.title).cofreFont(.navSmall).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .overlay(alignment: .topTrailing) { countBadge(badge(for: s)).padding(4) }
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 4) {
                PixelIcon(.bolt, size: 20)
                Text(verbatim: "JIT").cofreFont(.label).foregroundStyle(store.isJITReady ? Color.cofre.success : Color.cofre.muted)
            }
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(store.isJITReady ? Text("JIT ready") : Text("JIT not ready"))
            PixelIcon(.head, size: 26).padding(.vertical, 8)
                .accessibilityLabel(Text(verbatim: store.activeAccount?.name ?? "No account")).accessibilityHidden(false)
        }
        .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 12)
        .frame(width: theme.space.rail)
        .frame(maxHeight: .infinity)
        .background(Color.cofre.side.ignoresSafeArea())
        .overlay(alignment: .trailing) { Color.cofre.outline.frame(width: 2).ignoresSafeArea() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                AppIcon(size: 30)
                Text(verbatim: "Cofre").cofreFont(.title2).foregroundStyle(Color.cofre.ink)
            }
            .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 14)
            .accessibilityElement(children: .combine)
            ForEach(NavModel.Section.allCases, id: \.self) { s in
                navButton(s) { on in
                    HStack(spacing: 12) {
                        PixelIcon(s.glyph, size: 20).opacity(on ? 1 : 0.55)
                        Text(s.title).cofreFont(.nav).lineLimit(1)
                        Spacer(minLength: 0)
                        countBadge(badge(for: s))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
            }
            if !store.instances.isEmpty {
                SectionLabel(Text("Pinned")).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 2)
                ForEach(store.instances.prefix(3)) { inst in
                    Button {
                        nav.instance = inst.id; select(.instances)
                    } label: {
                        HStack(spacing: 12) {
                            InstanceGlyph(icon: inst.icon, size: 18)
                            Text(verbatim: inst.name).cofreFont(.nav).lineLimit(1).truncationMode(.tail)
                        }
                        .foregroundStyle(Color.cofre.muted)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .blockHover()
                    .blockFocusRing()
                }
            }
            Spacer(minLength: 12)
            VStack(spacing: 5) {
                Row(store.isJITReady ? LocalizedStringKey("JIT ready") : "JIT not ready", subtitle: "Auto at launch") {
                    PixelIcon(.bolt, size: 20)
                } trailing: {
                    Badge(store.isJITReady ? "On" : "Off", tone: store.isJITReady ? .success : .danger)
                }
                if let a = store.activeAccount {
                    Row(a.name, subtitle: a.kind, leading: { PixelIcon(.head, size: 22) })
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 16)
        .frame(width: theme.space.sidebar)
        .frame(maxHeight: .infinity)
        .background(Color.cofre.side.ignoresSafeArea())
        .overlay(alignment: .trailing) { Color.cofre.outline.frame(width: 2).ignoresSafeArea() }
    }

    private func navButton<L: View>(_ s: NavModel.Section, @ViewBuilder label: @escaping (Bool) -> L) -> some View {
        let on = nav.section == s
        return Button { select(s) } label: {
            label(on)
                .foregroundStyle(on ? Color.cofre.ink : Color.cofre.muted)
                .background(on ? Color.cofre.raised : Color.clear)
                .overlay(alignment: .leading) { if on { Color.cofre.accent.frame(width: style == .rail ? 3 : 4) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .blockHover()
        .blockFocusRing()
        .keyboardShortcut(s.shortcut, modifiers: .command)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityValue(badge(for: s) > 0 ? Text("\(badge(for: s)) updates") : Text(""))
    }

    @ViewBuilder private func countBadge(_ n: Int) -> some View {
        if n > 0 {
            Text(verbatim: "\(n)").cofreFont(.badge).foregroundStyle(Color.cofre.ink)
                .padding(.horizontal, 5).padding(.bottom, 1)
                .background(Color.cofre.tint(.warn))
                .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
                .accessibilityHidden(true)
        }
    }
}

/// Instance icon: PNG from the pack if any, else its pixel glyph and ore tint.
public struct InstanceGlyph: View {
    let icon: InstanceIcon, size: CGFloat
    public init(icon: InstanceIcon, size: CGFloat) { self.icon = icon; self.size = size }
    public var body: some View {
        if let data = icon.png, let img = UIImage(data: data) {
            Image(uiImage: img).interpolation(.none).resizable().frame(width: size, height: size).accessibilityHidden(true)
        } else {
            PixelIcon(icon.glyph, size: size, tint: icon.tintHex.map { Color(uiColor: UIColor(hex: $0)) })
        }
    }
}
