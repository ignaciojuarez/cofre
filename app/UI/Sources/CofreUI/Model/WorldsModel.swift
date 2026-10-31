#if canImport(UIKit)
import Foundation
import Observation
import CofreKit

@MainActor @Observable
public final class WorldsModel {
    public private(set) var worlds: [World] = []
    public private(set) var instance: Instance?
    public var error: String?
    public private(set) var undoLabel: String?
    private var store: WorldStore?
    private var deleted: WorldStore.TrashToken?

    public init() {}

    public func load(instanceID: String?, from instances: InstanceStore?) {
        guard let instances else { worlds = []; instance = nil; store = nil; return }
        do {
            let found = try instances.list().first { $0.id == instanceID } ?? instances.list().first
            instance = found
            store = found.map { WorldStore(instance: $0) }
            worlds = try store?.list() ?? []
            error = nil
            NSLog("[Cofre] worlds profile=%@ count=%ld", found?.id ?? "-", worlds.count)
        } catch let e { error = e.localizedDescription }
    }

    public func refresh() { guard let store else { return }; do { worlds = try store.list(); error = nil } catch let e { error = e.localizedDescription } }
    public func backUp(_ world: World) -> URL? { guard let store else { return nil }; return try? store.backUp(world.id) }
    public func export(_ world: World) -> URL? { guard let store else { return nil }; return try? store.export(world.id) }
    public func delete(_ world: World) { guard let store else { return }; do { deleted = try store.delete(world.id); worlds.removeAll { $0.id == world.id }; undoLabel = "Deleted \(world.displayName) · Undo" } catch let e { error = e.localizedDescription } }
    public func undoDelete() { guard let store, let deleted else { return }; do { try store.undo(deleted); self.deleted = nil; undoLabel = nil; refresh() } catch let e { error = e.localizedDescription } }
    public func copy(_ world: World, to target: Instance) { guard let store else { return }; do { try store.copy(world.id, to: target); error = nil } catch let e { error = e.localizedDescription } }
    public func `import`(_ url: URL) { guard let store else { return }; do { _ = try store.import(url); refresh() } catch let e { error = e.localizedDescription } }
}
#endif
