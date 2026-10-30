import Foundation

/// The game's real render size. Air's `video.resolution` scales each side of the screen's native pixels and draws
/// with nearest-neighbour filtering, so only whole divisors look sharp: each game pixel is 1×1, 2×2 or 3×3 screen pixels.
public struct RenderResolution: Equatable, Sendable {
    /// Native pixels, landscape.
    public let width: Int, height: Int

    public init(width: Int, height: Int) {
        self.width = max(width, height)
        self.height = min(width, height)
    }

    public enum Preset: Int, CaseIterable, Identifiable, Sendable {
        case full = 1, balanced, battery
        public var id: Self { self }
        public var name: String { ["Full", "Balanced", "Battery"][rawValue - 1] }
        /// Share of each side drawn: 1, ½, ⅓.
        public var scale: Double { 1 / Double(rawValue) }
    }

    /// Full and Balanced always; Battery only where ⅓ is exact.
    public var presets: [Preset] { Preset.allCases.filter { $0 != .battery || isSharp($0) } }

    /// Every game pixel covers the same whole block of screen pixels.
    public func isSharp(_ preset: Preset) -> Bool { width % preset.rawValue == 0 && height % preset.rawValue == 0 }

    /// The offered preset a saved scale stands for. Air stores a float percentage, so allow a little slack.
    public func preset(for scale: Double) -> Preset? { presets.first { abs($0.scale - scale) < 0.005 } }

    /// What Air renders at `scale` (it rounds each side): "1133 × 744".
    public func size(_ scale: Double) -> String {
        "\(Int((Double(width) * scale).rounded())) × \(Int((Double(height) * scale).rounded()))"
    }

    /// "Balanced · 1133 × 744", or "70% · 1586 × 1042" between presets.
    public func label(_ scale: Double) -> String {
        "\(preset(for: scale)?.name ?? Self.percent(scale)) · \(size(scale))"
    }

    public static func percent(_ scale: Double) -> String { "\(Int((scale * 100).rounded()))%" }

    /// Share of the screen's pixels drawn: 100%, 25%, 11%.
    public static func share(_ scale: Double) -> String { percent(scale * scale) }
}
