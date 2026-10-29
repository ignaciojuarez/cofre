#if canImport(UIKit)
    import SwiftUI

    // §2 #24 LogView: live or static, colored by tag. One VoiceOver element labelled "Log".

    public struct LogView: View {
        let lines: [LogLine], follow: Bool
        public init(lines: [LogLine], follow: Bool = true) {
            self.lines = lines
            self.follow = follow
        }

        public var body: some View {
            ScrollViewReader { proxy in
                ScrollView([.vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            (Text(verbatim: line.time + " ").foregroundColor(Color.cofre.muted)
                                + Text(verbatim: "[\(line.tag)] ").foregroundColor(tagColor(line))
                                + Text(verbatim: line.text).foregroundColor(Color.cofre.inkSoft))
                                .cofreFont(.code)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: lines.last?.id) { _, id in if follow, let id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            .background(Color.cofre.well)
            .overlay { Rectangle().strokeBorder(Color.cofre.outline, lineWidth: 2) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Log"))
            .accessibilityValue(Text(verbatim: lines.suffix(3).map(\.text).joined(separator: ". ")))
        }

        private func tagColor(_ line: LogLine) -> Color {
            switch line.level {
            case .warning: .cofre.warn
            case .error: .cofre.danger
            case .success: .cofre.success
            case .info: .cofre.accent
            }
        }
    }
#endif
