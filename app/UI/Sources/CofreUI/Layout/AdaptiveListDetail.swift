import SwiftUI

// §3.2 AdaptiveListDetail: compact pushes the detail; regular shows list + detail columns.
// Selection lives in NavModel, so a resize moves the same selection between the two forms.

public struct AdaptiveListDetail<Item: Hashable, L: View, D: View, P: View>: View {
    @Binding var selection: Item?
    let list: L
    let detail: (Item) -> D
    let placeholder: P
    var defaultSelection: Item?

    @Environment(\.widthClass) private var widthClass
    @State private var ownWidth: CGFloat = 1000

    public init(selection: Binding<Item?>, defaultSelection: Item? = nil, @ViewBuilder list: () -> L,
                @ViewBuilder detail: @escaping (Item) -> D, @ViewBuilder placeholder: () -> P) {
        _selection = selection; self.defaultSelection = defaultSelection; self.list = list(); self.detail = detail; self.placeholder = placeholder()
    }

    public var body: some View {
        let listWidth: CGFloat = widthClass == .expanded ? 350 : 330
        let sideBySide = widthClass != .compact && ownWidth >= listWidth + 360
        Group {
            if sideBySide {
                HStack(spacing: 0) {
                    list
                        .frame(width: listWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(Color.cofre.side.opacity(0.55))
                        .overlay(alignment: .trailing) { Color.cofre.outline.frame(width: 2) }
                        .zIndex(1)
                    NavigationStack {
                        Group {
                            if let item = selection ?? defaultSelection { detail(item).id(item) } else { placeholder }
                        }
                        .toolbar(.hidden, for: .navigationBar)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background { PageBackground() }
                    }
                    .environment(\.widthClass, ownWidth - listWidth >= 700 ? widthClass : .medium)
                }
            } else {
                NavigationStack {
                    list
                        .toolbar(.hidden, for: .navigationBar)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background { PageBackground() }
                        .navigationDestination(item: $selection) { item in
                            detail(item)
                                .environment(\.isPushed, true)
                                .toolbar(.hidden, for: .navigationBar)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .background { PageBackground() }
                        }
                }
                .environment(\.widthClass, .compact)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ownWidth = $0 }
    }
}

public extension AdaptiveListDetail where P == DetailPlaceholder {
    init(selection: Binding<Item?>, defaultSelection: Item? = nil, @ViewBuilder list: () -> L, @ViewBuilder detail: @escaping (Item) -> D) {
        self.init(selection: selection, defaultSelection: defaultSelection, list: list, detail: detail) { DetailPlaceholder() }
    }
}

public struct DetailPlaceholder: View {
    public init() {}
    public var body: some View {
        EmptyState("Nothing selected", message: "Pick an item from the list.", icon: .chest)
    }
}
