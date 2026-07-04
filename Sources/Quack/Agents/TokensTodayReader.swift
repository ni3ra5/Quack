import Foundation
import SQLite3

/// Optional enrichment: today's output tokens from the third-party usage.db
/// aggregator (~/.claude/usage.db), read-only. nil (db missing, locked, or
/// schema mismatch) simply hides the header pill — never an error state.
enum TokensTodayReader {
    static func todayOutputTokens(dbPath: String, now: Date = Date()) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        // turns.timestamp is ISO-8601 UTC; compare lexically against local
        // midnight expressed in UTC.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        let cutoff = fmt.string(from: Calendar.current.startOfDay(for: now))

        var stmt: OpaquePointer?
        let sql = "SELECT COALESCE(SUM(output_tokens), 0) FROM turns WHERE timestamp >= ?1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, cutoff, -1, transient)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let total = sqlite3_column_int64(stmt, 0)
        return total > 0 ? Int(total) : nil
    }
}
