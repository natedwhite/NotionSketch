import Foundation

enum WhiteboardZIndex {

    static func renderSorted(_ objects: [WhiteboardObject]) -> [WhiteboardObject] {
        objects.sorted { a, b in
            if a.zIndex != b.zIndex { return a.zIndex < b.zIndex }
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id.uuidString < b.id.uuidString
        }
    }

    static func topZIndex(of objects: [WhiteboardObject]) -> Int {
        guard !objects.isEmpty else { return 0 }
        return objects.map(\.zIndex).max()!
    }

    static func bottomZIndex(of objects: [WhiteboardObject]) -> Int {
        guard !objects.isEmpty else { return 0 }
        return objects.map(\.zIndex).min()!
    }
}
