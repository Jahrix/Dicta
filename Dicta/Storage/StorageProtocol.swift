import Foundation

protocol AppDataStoring {
    func load() throws -> AppData
    func save(_ data: AppData) throws
}
