import AppKit
import Darwin

/// The public window list includes windows from other Spaces while Mission Control
/// is open. SkyLight exposes the active Space IDs, but is optional on macOS.
final class ActiveSpaces {
    private typealias Connection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    func current() -> Set<UInt64>? {
        guard let library, let c = dlsym(library, "CGSMainConnectionID"),
              let s = dlsym(library, "CGSCopyManagedDisplaySpaces") else { return nil }
        let connection = unsafeBitCast(c, to: Connection.self)
        let copy = unsafeBitCast(s, to: CopySpaces.self)
        guard let displays = copy(connection())?.takeRetainedValue() as? [[String: Any]], !displays.isEmpty else { return nil }
        let ids = displays.compactMap { ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber }.map(\.uint64Value)
        return ids.count == displays.count ? Set(ids) : nil
    }

    static func includes(_ identifier: String?, active: Set<UInt64>?) -> Bool {
        guard let active, let identifier, let separator = identifier.range(of: ".space.", options: .backwards),
              let id = UInt64(identifier[separator.upperBound...]) else { return true }
        return active.contains(id)
    }
}
