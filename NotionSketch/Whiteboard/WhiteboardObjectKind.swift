import Foundation
import UIKit

enum ShapeKind: String, Codable, CaseIterable {
    case triangle
    case square
    case circle
    case arrow
    case line
    case thickArrow
    case capsule
}

struct RGBAColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(r: Double = 0, g: Double = 0, b: Double = 0, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    nonisolated init(uiColor: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        self.r = Double(red)
        self.g = Double(green)
        self.b = Double(blue)
        self.a = Double(alpha)
    }

    nonisolated var uiColor: UIColor {
        .init(
            red: CGFloat(r),
            green: CGFloat(g),
            blue: CGFloat(b),
            alpha: CGFloat(a)
        )
    }
}

enum WhiteboardObjectKind: Codable, Equatable {
    case freehandPencilKit(drawingDataBase64: String)
    case shape(ShapeKind)
    case sticky(text: String)
    case textBox(text: String)

    enum CodingKeys: String, CodingKey {
        case type
        case drawingDataBase64
        case shapeKind
        case text
    }

    enum TypeString: String {
        case freehand
        case shape
        case sticky
        case textBox
    }

    private var typeString: TypeString {
        switch self {
        case .freehandPencilKit: return .freehand
        case .shape: return .shape
        case .sticky: return .sticky
        case .textBox: return .textBox
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeRaw = try container.decode(String.self, forKey: .type)

        guard let typeValue = TypeString(rawValue: typeRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown WhiteboardObjectKind type: \(typeRaw)"
            )
        }

        switch typeValue {
        case .freehand:
            let dataBase64 = try container.decode(String.self, forKey: .drawingDataBase64)
            self = .freehandPencilKit(drawingDataBase64: dataBase64)
        case .shape:
            let kind = try container.decode(ShapeKind.self, forKey: .shapeKind)
            self = .shape(kind)
        case .sticky:
            let text = try container.decode(String.self, forKey: .text)
            self = .sticky(text: text)
        case .textBox:
            let text = try container.decode(String.self, forKey: .text)
            self = .textBox(text: text)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeString.rawValue, forKey: .type)

        switch self {
        case .freehandPencilKit(let dataBase64):
            try container.encode(dataBase64, forKey: .drawingDataBase64)
        case .shape(let kind):
            try container.encode(kind, forKey: .shapeKind)
        case .sticky(let text):
            try container.encode(text, forKey: .text)
        case .textBox(let text):
            try container.encode(text, forKey: .text)
        }
    }
}
