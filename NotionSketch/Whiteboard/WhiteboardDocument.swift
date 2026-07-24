/*
 Migration plan:
 - Current storage = PKDrawing encoded string in the Notion page body ("Image Data" toggle / code blocks).
 - New storage = WhiteboardDocument JSON in the page body.
 - Interim: both formats supported during migration; detection & round-trip land in later tasks
   (Prompt 2 for the local model, Prompt 10 for sync).
*/

import Foundation

struct WhiteboardDocument: Codable, Equatable {
    var objects: [WhiteboardObject] = []
    var selection: WhiteboardSelection = .init()

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    func toJSONString() -> String? {
        guard let data = try? Self.encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSONString(_ s: String) -> WhiteboardDocument? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(WhiteboardDocument.self, from: data)
    }
}
