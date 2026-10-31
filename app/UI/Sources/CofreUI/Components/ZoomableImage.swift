#if canImport(UIKit)
    import SwiftUI
    import UIKit

    // Pinch and double-tap zoom for the gallery viewer. SwiftUI on iOS 17 has no reliable zoomable scroll view, so a
    // small UIScrollView hosts the SwiftUI content. At 1× it leaves sideways swipes to the pager and turns a swipe down
    // into `onDismiss`.

    struct ZoomableImage: UIViewRepresentable {
        /// Pages off screen go back to 1×, so paging back never lands on a zoomed image.
        let isCurrent: Bool
        var onDismiss: () -> Void = {}
        /// Set only when there's no sliding pager (Reduce Motion): -1 for the previous page, +1 for the next.
        var onSwipe: ((Int) -> Void)?
        let content: AnyView
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        init(
            isCurrent: Bool, onDismiss: @escaping () -> Void = {}, onSwipe: ((Int) -> Void)? = nil,
            @ViewBuilder content: () -> some View
        ) {
            self.isCurrent = isCurrent
            self.onDismiss = onDismiss
            self.onSwipe = onSwipe
            self.content = AnyView(content())
        }

        func makeCoordinator() -> Coordinator { Coordinator(self) }

        func makeUIView(context: Context) -> UIScrollView {
            let scroll = ZoomScrollView()
            scroll.delegate = context.coordinator
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = 4
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.backgroundColor = .clear
            let host = UIHostingController(rootView: content)
            host.view.backgroundColor = .clear
            host.safeAreaRegions = []
            scroll.addSubview(host.view)
            scroll.zoomView = host.view
            context.coordinator.host = host

            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            scroll.addGestureRecognizer(doubleTap)
            for direction: UISwipeGestureRecognizer.Direction in [.down, .left, .right] {
                let swipe = UISwipeGestureRecognizer(
                    target: context.coordinator, action: #selector(Coordinator.swiped(_:)))
                swipe.direction = direction
                swipe.delegate = context.coordinator
                scroll.addGestureRecognizer(swipe)
            }
            return scroll
        }

        func updateUIView(_ scroll: UIScrollView, context: Context) {
            context.coordinator.parent = self
            context.coordinator.host?.rootView = content
            scroll.bouncesZoom = !reduceMotion
            if !isCurrent, scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: false) }
        }

        @MainActor final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
            var parent: ZoomableImage
            var host: UIHostingController<AnyView>?
            init(_ parent: ZoomableImage) { self.parent = parent }

            func viewForZooming(in scrollView: UIScrollView) -> UIView? { host?.view }

            /// Double tap zooms into the tapped spot, or back out. No spring with Reduce Motion.
            @objc func doubleTapped(_ tap: UITapGestureRecognizer) {
                guard let scroll = tap.view as? UIScrollView else { return }
                let animated = !parent.reduceMotion
                if scroll.zoomScale > 1 {
                    scroll.setZoomScale(1, animated: animated)
                } else {
                    let point = tap.location(in: host?.view)
                    let scale: CGFloat = 2.5
                    let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                    let rect = CGRect(
                        origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size)
                    scroll.zoom(to: rect, animated: animated)
                }
            }

            @objc func swiped(_ swipe: UISwipeGestureRecognizer) {
                switch swipe.direction {
                case .down: parent.onDismiss()
                case .left: parent.onSwipe?(1)
                case .right: parent.onSwipe?(-1)
                default: break
                }
            }

            /// Swipes only count at 1×; zoomed in, a drag pans the image. Sideways swipes only without a pager.
            func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
                guard let swipe = gesture as? UISwipeGestureRecognizer,
                    let scroll = swipe.view as? UIScrollView
                else { return true }
                return scroll.zoomScale <= 1.01 && (swipe.direction == .down || parent.onSwipe != nil)
            }

            func gestureRecognizer(
                _ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
            ) -> Bool { true }
        }
    }

    /// Keeps the hosted content filling the scroll view at 1×; zooming scales it from there.
    private final class ZoomScrollView: UIScrollView {
        weak var zoomView: UIView?
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let zoomView, zoomScale == 1, !isZooming else { return }
            zoomView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }
#endif
