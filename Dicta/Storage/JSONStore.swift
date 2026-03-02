import Foundation

final class JSONStore: AppDataStoring {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = try AppSupportPaths.dataFileURL()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load() throws -> AppData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppData()
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AppData.self, from: data)
    }

    func save(_ data: AppData) throws {
        let encoded = try encoder.encode(data)
        let tempURL = fileURL.appendingPathExtension("tmp")
        try encoded.write(to: tempURL, options: [.atomic])

        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}
