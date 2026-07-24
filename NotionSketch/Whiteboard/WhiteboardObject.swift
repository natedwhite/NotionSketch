import Foundation

struct WhiteboardObject: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: WhiteboardObjectKind
    var zIndex: Int

    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var rotation: Double

    var fill: RGBAColor
    var stroke: RGBAColor
    var strokeWidth: Double
    var textColor: RGBAColor?

    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: WhiteboardObjectKind,
        zIndex: Int = 0,
        x: Double = 0,
        y: Double = 0,
        width: Double = 100,
        height: Double = 100,
        rotation: Double = 0,
        fill: RGBAColor = RGBAColor(r: 1, g: 1, b: 1, a: 0),
        stroke: RGBAColor = RGBAColor(),
        strokeWidth: Double = 2,
        textColor: RGBAColor? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.zIndex = zIndex
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.fill = fill
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.textColor = textColor
        self.createdAt = createdAt
    }
}


