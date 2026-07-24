import Foundation

enum WhiteboardTool: Equatable {
    case pan
    case draw
    case shape(ShapeKind)
    case sticky
    case text
}
