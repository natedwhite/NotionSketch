import CoreGraphics
import Foundation

struct WhiteboardSelection: Codable, Equatable {
    var selectedIDs: Set<UUID> = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case selectedIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let array = try container.decode([UUID].self, forKey: .selectedIDs)
        self.selectedIDs = Set(array)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(selectedIDs), forKey: .selectedIDs)
    }

    func selectionBounds(in objects: [WhiteboardObject]) -> CGRect? {
        guard !selectedIDs.isEmpty else { return nil }

        let selected = objects.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }

        var bounds = CGRect(
            x: selected[0].x,
            y: selected[0].y,
            width: selected[0].width,
            height: selected[0].height
        )

        for obj in selected.dropFirst() {
            let frame = CGRect(x: obj.x, y: obj.y, width: obj.width, height: obj.height)
            bounds = bounds.union(frame)
        }

        return bounds
    }
}
