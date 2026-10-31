#if canImport(UIKit)
    import SwiftUI
    import CofreKit

    // Full-screen gallery viewer (rich mod pages §3): swipe between images, pinch or double-tap to zoom, swipe down or
    // ✕ to close. The thumbnail shows at once and the full image loads on top. Reduce Motion cross-fades between
    // pages instead of sliding. VoiceOver reads each page as "title, caption, image 2 of 4".

    public struct GalleryViewer: View {
        let projectID: String, gallery: Gallery
        @State private var index: Int
        @Environment(\.dismiss) private var dismiss
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let theme = CofreTheme.standard

        /// `start` is an index into `gallery.images`.
        public init(projectID: String, gallery: Gallery, start: Int) {
            self.projectID = projectID
            self.gallery = gallery
            _index = State(initialValue: gallery.clamped(start))
        }

        public var body: some View {
            ZStack {
                Color.cofre.lip.ignoresSafeArea()
                if !gallery.images.isEmpty { pager.ignoresSafeArea() }
            }
            .overlay(alignment: .top) { topBar }
            .overlay(alignment: .bottom) { caption }
            .accessibilityAction(.escape) { dismiss() }
            .onAppear { NSLog("%@", Gallery.openLog(id: projectID, index: index)) }
        }

        @ViewBuilder private var pager: some View {
            if reduceMotion {
                // No sliding: the page swaps with a short cross-fade.
                ZStack { page(index).id(index).transition(.opacity) }
                    .animation(.linear(duration: theme.motion.reducedCrossfade), value: index)
                    .accessibilityScrollAction { edge in
                        switch edge {
                        case .leading: step(-1)
                        case .trailing: step(1)
                        default: break
                        }
                    }
            } else {
                TabView(selection: $index) {
                    ForEach(gallery.images.indices, id: \.self) { i in page(i).tag(i) }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }

        private func page(_ i: Int) -> some View {
            let image = gallery.images[i]
            return ZoomableImage(
                isCurrent: i == index, onDismiss: { dismiss() }, onSwipe: reduceMotion ? { step($0) } : nil
            ) {
                GalleryImage(thumb: image.thumb, full: Gallery.loadsFull(i, current: index) ? image.full : nil)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: gallery.spokenLabel(i)))
            .accessibilityAddTraits(.isImage)
        }

        private func step(_ by: Int) { index = gallery.clamped(index + by) }

        private var topBar: some View {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    PixelIcon(.cross, size: 14)
                }
                .buttonStyle(.block(size: .small))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
                Spacer()
                // VoiceOver already hears the position on the page itself.
                Text(verbatim: gallery.counter(index))
                    .cofreFont(.label)
                    .foregroundStyle(Color.cofre.inkSoft)
                    .accessibilityHidden(true)
                Spacer()
                if gallery.images.indices.contains(index) {
                    ShareLink(item: gallery.images[index].full) { Text("Share") }.buttonStyle(.block(size: .small))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }

        @ViewBuilder private var caption: some View {
            if gallery.images.indices.contains(index) {
                let image = gallery.images[index]
                if image.title != nil || image.caption != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = image.title {
                            Text(verbatim: title).cofreFont(.rowTitle).foregroundStyle(Color.cofre.ink)
                        }
                        if let caption = image.caption {
                            Text(verbatim: caption).cofreFont(.secondary).foregroundStyle(Color.cofre.inkSoft)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.cofre.lip.opacity(0.8))
                    // Read as part of the page's label.
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    #if DEBUG
        #Preview("Viewer · Iris") {
            GalleryViewer(projectID: "YL57xq9U", gallery: Gallery(.galleryPreview), start: 1)
        }
    #endif
#endif
