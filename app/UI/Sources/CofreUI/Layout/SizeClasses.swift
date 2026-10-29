#if canImport(UIKit)
    import SwiftUI

    /// Size classes from the measured window, not UIKit. Air reports every trait collection as regular/regular
    /// (its `UIKit+hook.m`), which gave iPhones the iPad layout. `CofreRootView` measures; sheets and covers reapply
    /// the root's values with `sizeClasses(nil)`, because their hosting controllers read UIKit's again.
    public struct SizeClasses: Equatable, Sendable {
        public var horizontal: UserInterfaceSizeClass
        public var vertical: UserInterfaceSizeClass

        /// Regular from 700 pt wide (every full-screen iPad, big iPhones in landscape). Compact under 500 pt tall.
        public init(_ size: CGSize) {
            horizontal = size.width >= 700 ? .regular : .compact
            vertical = size.height >= 500 ? .regular : .compact
        }
    }

    extension EnvironmentValues {
        @Entry var sizeClasses: SizeClasses? = nil
    }

    extension View {
        /// Overrides UIKit's size classes with `classes`, or with the ones the root measured when `nil`.
        func sizeClasses(_ classes: SizeClasses?) -> some View { modifier(ApplySizeClasses(classes: classes)) }
    }

    private struct ApplySizeClasses: ViewModifier {
        let classes: SizeClasses?
        @Environment(\.sizeClasses) private var inherited

        func body(content: Content) -> some View {
            let c = classes ?? inherited
            content
                .transformEnvironment(\.horizontalSizeClass) { if let c { $0 = c.horizontal } }
                .transformEnvironment(\.verticalSizeClass) { if let c { $0 = c.vertical } }
                .environment(\.sizeClasses, c)
        }
    }
#endif
