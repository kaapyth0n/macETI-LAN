import Foundation
import CSQLite

public enum CatalogReader {
    public static let maximumBytes = 50 * 1024 * 1024

    public static func read(_ url: URL) throws -> Catalog {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size > 0, size <= maximumBytes else {
            throw ETIError("The catalog must be a regular SQLite file smaller than 50 MB.")
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw ETIError("Cannot open the catalog. Wait for Resilio to finish downloading game.db.")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1_000)
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, 1_000_000)
        sqlite3_limit(db, SQLITE_LIMIT_SQL_LENGTH, 10_000)
        sqlite3_exec(db, "PRAGMA trusted_schema=OFF; PRAGMA query_only=ON; BEGIN", nil, nil, nil)
        defer { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) }

        let integrity = try prepare(db, "PRAGMA quick_check")
        defer { sqlite3_finalize(integrity) }
        guard sqlite3_step(integrity) == SQLITE_ROW, column(integrity, 0) == "ok" else {
            throw ETIError("The catalog failed SQLite integrity validation. Wait for sync to complete and retry.")
        }

        // Do not allow an imported database to replace games with an executable SQL view.
        let schema = try prepare(db, "SELECT type FROM sqlite_master WHERE name='games'")
        defer { sqlite3_finalize(schema) }
        guard sqlite3_step(schema) == SQLITE_ROW, column(schema, 0) == "table" else {
            throw ETIError("This file does not contain the ETI games table.")
        }
        let columnsStatement = try prepare(db, "PRAGMA table_info(games)")
        defer { sqlite3_finalize(columnsStatement) }
        var columns = Set<String>()
        while sqlite3_step(columnsStatement) == SQLITE_ROW { columns.insert(column(columnsStatement, 1)) }
        // Column names below are a fixed allowlist, never values taken from the database.
        let optionalColumns = ["game_release", "game_publisher", "game_maxplayers", "genre_id"]
            .map { columns.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        var genres: [Int: String] = [:]
        let genreSchema = try prepare(db, "SELECT type FROM sqlite_master WHERE name='genre'")
        defer { sqlite3_finalize(genreSchema) }
        if sqlite3_step(genreSchema) == SQLITE_ROW, column(genreSchema, 0) == "table",
           let genreStatement = try? prepare(db, "SELECT genre_id, genre_en FROM genre LIMIT 1000") {
            defer { sqlite3_finalize(genreStatement) }
            while sqlite3_step(genreStatement) == SQLITE_ROW {
                genres[Int(sqlite3_column_int(genreStatement, 0))] = cleanMetadata(column(genreStatement, 1))
            }
        }
        let statement = try prepare(db, """
            SELECT game_id, game_title, game_version, game_size, game_key, \(optionalColumns)
            FROM games ORDER BY db_id LIMIT 5001
            """)
        defer { sqlite3_finalize(statement) }
        var games: [Game] = []
        var seen = Set<String>()
        var skipped = 0
        var rows = 0
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw ETIError("The catalog is incomplete or unreadable.") }
            rows += 1
            guard rows <= 5_000 else { throw ETIError("The catalog exceeds the supported 5,000 entries.") }
            let id = column(statement, 0)
            let title = column(statement, 1)
            let revision = column(statement, 2)
            guard validID(id), !title.isEmpty, title.count <= 300,
                  !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  revision.count <= 64,
                  !revision.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                skipped += 1
                continue
            }
            guard seen.insert(id).inserted else { throw ETIError("The catalog contains duplicate game identifiers.") }
            // Only numeric sizes are accepted. Never silently interpret arbitrary text as zero.
            let sizeType = sqlite3_column_type(statement, 3)
            let size = sqlite3_column_double(statement, 3)
            let validSize = (sizeType == SQLITE_FLOAT || sizeType == SQLITE_INTEGER) && size.isFinite && size > 0 && size < 100_000
            var game = Game(id: id, title: title, packageRevision: revision,
                              reportedSizeGB: validSize ? size : nil,
                              readOnlyKey: ReadOnlyKey(column(statement, 4)))
            game.metadata.year = cleanMetadata(column(statement, 5))
            game.metadata.publisher = cleanMetadata(column(statement, 6))
            let players = Int(sqlite3_column_int(statement, 7))
            game.metadata.maximumPlayers = players > 0 && players <= 10_000 ? players : nil
            game.metadata.genre = genres[Int(sqlite3_column_int(statement, 8))] ?? ""
            games.append(game)
        }
        guard !games.isEmpty else { throw ETIError("No usable games were found in this catalog.") }
        return Catalog(games: games, skippedRows: skipped)
    }

    public static func validID(_ id: String) -> Bool {
        id.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil
    }

    private static func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ETIError("The catalog schema is not supported, or its download is incomplete.")
        }
        return statement
    }

    private static func column(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private static func cleanMetadata(_ value: String) -> String {
        guard value.count <= 300, !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return "" }
        return value
    }
}
