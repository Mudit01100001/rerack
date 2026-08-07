import Foundation

/// Shared local photo storage for the one photo type that exists in V1 today
/// (a cardio console snapshot) and the one that ships in M7 (the workout
/// finish-flow photo, PRD §9.4) — both are "save a JPEG, keep the filename"
/// with no other logic, so one utility covers both rather than duplicating it.
enum PhotoStorage {
    private static var directory: URL {
        let dir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func save(_ data: Data) -> String? {
        let filename = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return filename
        } catch {
            return nil
        }
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    static func delete(_ filename: String) {
        try? FileManager.default.removeItem(at: url(for: filename))
    }
}
