import Foundation

public enum CofreBreadcrumb {
    public static func line(action: String, details: String = "") -> String {
        let suffix = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? "[Cofre] action \(action)" : "[Cofre] action \(action) \(suffix)"
    }
    public static func log(_ action: String, details: String = "") { NSLog("%@", line(action: action, details: details)) }
}

public enum OptionsDiff {
    public static func changes(before: String, after: String) -> [String] {
        func parse(_ text: String) -> [String: String] {
            text.split(whereSeparator: \.isNewline).reduce(into: [:]) { result, line in
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { result[parts[0]] = parts[1] }
            }
        }
        let old = parse(before), new = parse(after)
        return Set(old.keys).union(new.keys).sorted().compactMap { key in
            guard old[key] != new[key], let value = new[key] else { return nil }
            return "[Cofre] options changed \(key): \(old[key] ?? "<unset>") → \(value)"
        }
    }
}
