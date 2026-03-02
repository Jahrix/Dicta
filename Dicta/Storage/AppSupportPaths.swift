import Foundation

enum AppSupportPaths {
    static let appName = "Dicta"
    static let dataFileName = "dicta_data.json"

    static func applicationSupportDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppSupportPathsError.applicationSupportUnavailable
        }
        let dirURL = baseURL.appendingPathComponent(appName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        return dirURL
    }

    static func dataFileURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent(dataFileName, isDirectory: false)
    }
}

enum AppSupportPathsError: Error {
    case applicationSupportUnavailable
}
