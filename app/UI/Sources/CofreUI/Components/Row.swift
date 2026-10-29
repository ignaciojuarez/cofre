import SwiftUI

// §2 #4 Row: leading · title/subtitle · trailing. One VoiceOver element per row.

public enum RowStyle: Sendable { case regular, big }

public struct Row<Leading: View, Trailing: View>: View {
    let title: Text
    let subtitle: AnyView?
    let isSelected: Bool
    let leading: Leading
    let trailing: Trailing
    var style: RowStyle = .regular
    var isDimmed = false

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        _ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isSelected: Bool = false,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = Text(title)
        self.subtitle = subtitle.map { AnyView(SubtitleText(text: Text($0))) }
        self.isSelected = isSelected
        self.leading = leading()
        self.trailing = trailing()
    }

    @_disfavoredOverload
    public init(
        _ title: String, subtitle: String? = nil, isSelected: Bool = false,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = Text(verbatim: title)
        self.subtitle = subtitle.map { AnyView(SubtitleText(text: Text(verbatim: $0))) }
        self.isSelected = isSelected
        self.leading = leading()
        self.trailing = trailing()
    }

    /// Subtitle built from views (e.g. a Badge plus text).
    public init<S: View>(
        _ title: String, isSelected: Bool = false, @ViewBuilder subtitleView: () -> S,
        @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = Text(verbatim: title)
        self.subtitle = AnyView(subtitleView())
        self.isSelected = isSelected
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        let stacked = typeSize.isAccessibilitySize
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                title.cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).lineLimit(stacked ? nil : 1)
                if let subtitle { subtitle }
                if stacked && Trailing.self != EmptyView.self { trailing.padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !stacked { trailing }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, style == .big ? 10 : 8)
        .frame(minHeight: 44)
        .block(.panel, selected: isSelected)
        .blockHover()
        .opacity(isDimmed ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    public func rowStyle(_ style: RowStyle) -> Self {
        var c = self
        c.style = style
        return c
    }
    public func dimmed(_ dimmed: Bool = true) -> Self {
        var c = self
        c.isDimmed = dimmed
        return c
    }
}

struct SubtitleText: View {
    let text: Text
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        text.cofreFont(.caption).foregroundStyle(Color.cofre.muted).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }
}

extension Row where Leading == EmptyView {
    public init(
        _ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isSelected: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title, subtitle: subtitle, isSelected: isSelected, leading: { EmptyView() }, trailing: trailing)
    }
    @_disfavoredOverload
    public init(
        _ title: String, subtitle: String? = nil, isSelected: Bool = false, @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title, subtitle: subtitle, isSelected: isSelected, leading: { EmptyView() }, trailing: trailing)
    }
}

extension Row where Trailing == EmptyView {
    public init(
        _ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isSelected: Bool = false,
        @ViewBuilder leading: () -> Leading
    ) {
        self.init(title, subtitle: subtitle, isSelected: isSelected, leading: leading, trailing: { EmptyView() })
    }
    @_disfavoredOverload
    public init(_ title: String, subtitle: String? = nil, isSelected: Bool = false, @ViewBuilder leading: () -> Leading)
    {
        self.init(title, subtitle: subtitle, isSelected: isSelected, leading: leading, trailing: { EmptyView() })
    }
}

extension Row where Leading == EmptyView, Trailing == EmptyView {
    public init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isSelected: Bool = false) {
        self.init(
            title, subtitle: subtitle, isSelected: isSelected, leading: { EmptyView() }, trailing: { EmptyView() })
    }
    @_disfavoredOverload
    public init(_ title: String, subtitle: String? = nil, isSelected: Bool = false) {
        self.init(
            title, subtitle: subtitle, isSelected: isSelected, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Index lead ("01") for step lists.
public struct RowIndex: View {
    let n: Int
    public init(_ n: Int) { self.n = n }
    public var body: some View {
        Text(verbatim: String(format: "%02d", n)).cofreFont(.label).foregroundStyle(Color.cofre.muted)
            .accessibilityHidden(true)
    }
}

/// Trailing chevron for rows that push.
public struct Chevron: View {
    public init() {}
    public var body: some View {
        Text(verbatim: "›").cofreFont(.button).foregroundStyle(Color.cofre.muted).accessibilityHidden(true)
    }
}

/// Pressed state for tappable rows: the block sinks into a well (§1.4).
public struct RowButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    Color.cofre.well.opacity(0.55).overlay(alignment: .top) { Color.cofre.lip.frame(height: 2) }
                        .padding(2).allowsHitTesting(false)
                }
            }
            .blockFocusRing()
    }
}

/// A row whose trailing switch toggles the whole row (toggle trait, one element).
public struct ToggleRow: View {
    let title: Text, subtitle: Text?
    @Binding var isOn: Bool

    public init(_ title: LocalizedStringKey, subtitle: LocalizedStringKey? = nil, isOn: Binding<Bool>) {
        self.title = Text(title)
        self.subtitle = subtitle.map { Text($0) }
        _isOn = isOn
    }
    @_disfavoredOverload
    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = Text(verbatim: title)
        self.subtitle = subtitle.map { Text(verbatim: $0) }
        _isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                title.cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                if let subtitle { SubtitleText(text: subtitle) }
            }
        }
        .toggleStyle(.block)
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(minHeight: 44)
        .block(.panel)
        .blockHover()
    }
}

/// Row that shows a value and pushes or opens a menu ("Renderer · MobileGlues ›").
public struct ValueRow: View {
    let title: Text, value: Text, accent: Bool, chevron: Bool
    public init(_ title: LocalizedStringKey, value: String, accent: Bool = false, chevron: Bool = true) {
        self.title = Text(title)
        self.value = Text(verbatim: value)
        self.accent = accent
        self.chevron = chevron
    }
    public var body: some View {
        HStack(spacing: 10) {
            title.cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                value
                if chevron { Text(verbatim: "›").accessibilityHidden(true) }
            }
            .cofreFont(.label).foregroundStyle(accent ? Color.cofre.accent : Color.cofre.muted).lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(minHeight: 44)
        .block(.panel)
        .blockHover()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
