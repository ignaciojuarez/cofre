import Foundation

/// Java heap (-Xmx) policy. Cofre owns it; the engine only receives the result.
/// More heap than the game needs only slows GC and invites a jetsam kill, which closes the whole app.
public enum JavaHeap {
    /// Memory outside the heap: GL driver, textures, metaspace, code cache, thread stacks.
    /// Tuned on a 3 GB iPhone, where a smaller reserve was killed while loading.
    public static let nativeReserveMB = 1200
    public static let minimumMB = 512

    /// What the game needs, capped at half the device.
    public static func autoMB(loader: Instance.Loader, modCount: Int, physicalMB: Int) -> Int {
        let target =
            switch loader {
            case .forge, .neoforge: modCount > 100 ? 6144 : 4096
            case .fabric, .quilt: modCount > 0 ? 3072 : 2048
            case .vanilla, .unknown: 2048
            }
        return min(target, physicalMB / 2)
    }

    /// Fits a requested heap (auto or manual) into the memory iOS lets this process use right now.
    /// `availableMB` is `os_proc_available_memory()` sampled just before the JVM starts; 0 means unknown.
    /// Low headroom shrinks the heap; it never falls back to a larger guess.
    public static func clamp(_ requestedMB: Int, availableMB: Int) -> Int {
        let limit = availableMB > 0 ? availableMB - nativeReserveMB : requestedMB
        return max(minimumMB, min(requestedMB, limit) / 128 * 128)
    }
}
