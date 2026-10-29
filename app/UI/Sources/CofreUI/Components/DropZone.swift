import SwiftUI
import UniformTypeIdentifiers

// §2 #23 DropZone: a button ("Choose …") that also accepts drops. Drop is never the only path.

public struct DropZone: View {
    let title: LocalizedStringKey, detail: LocalizedStringKey?, glyph: PixelGlyph, types: [UTType]
    let onDrop: ([URL]) -> Void, onChoose: () -> Void
    @State private var targeted = false

    public init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, glyph: PixelGlyph = .paper, types: [UTType],
                onDrop: @escaping ([URL]) -> Void, onChoose: @escaping () -> Void) {
        self.title = title; self.detail = detail; self.glyph = glyph; self.types = types; self.onDrop = onDrop; self.onChoose = onChoose
    }

    public var body: some View {
        Button(action: onChoose) {
            VStack(spacing: 6) {
                PixelIcon(glyph, size: 30)
                Text(title).cofreFont(.button).foregroundStyle(Color.cofre.ink).multilineTextAlignment(.center)
                if let detail { Text(detail).cofreFont(.label).foregroundStyle(Color.cofre.muted).multilineTextAlignment(.center) }
            }
            .padding(.horizontal, 12).padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(targeted ? Color.cofre.tint(.accent, amount: 0.14) : Color.cofre.well)
            .overlay {
                Rectangle().strokeBorder(targeted ? Color.cofre.accent : Color.cofre.muted, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(6)
            }
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .blockHover()
        .blockFocusRing()
        .onDrop(of: types, isTargeted: $targeted) { providers in
            let group = DispatchGroup(), box = URLBox()
            for p in providers {
                guard let type = types.first(where: { p.hasItemConformingToTypeIdentifier($0.identifier) }) else { continue }
                group.enter()
                _ = p.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                    if let url {
                        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.removeItem(at: copy)
                        if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { box.append(copy) }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) { let urls = box.urls; if !urls.isEmpty { onDrop(urls) } }
            return true
        }
    }
}

private final class URLBox: @unchecked Sendable {
    private let lock = NSLock(); private var items: [URL] = []
    func append(_ u: URL) { lock.withLock { items.append(u) } }
    var urls: [URL] { lock.withLock { items } }
}
