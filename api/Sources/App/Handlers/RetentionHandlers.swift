import Vapor
import Fluent
import SQLKit

enum RetentionComputation {
    static let minDays = 1
    static let maxDays = 36500

    static func normalizeDays(_ requestedDays: Int?) -> Int {
        let days = requestedDays ?? 365
        return max(minDays, min(days, maxDays))
    }

    static func cutoff(now: Date = Date(), olderThanDays: Int) -> Date {
        let safeDays = max(minDays, min(olderThanDays, maxDays))
        let seconds = TimeInterval(safeDays) * 24 * 60 * 60
        return now.addingTimeInterval(-seconds)
    }

    static func cutoffString(_ cutoff: Date) -> String {
        String(Int64(cutoff.timeIntervalSince1970))
    }
}

func cleanupOldQuests(_ req: Request) async throws -> QuestRetentionCleanupResponseDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let body = try req.content.decode(QuestRetentionCleanupRequestDTO.self)
    let olderThanDays = RetentionComputation.normalizeDays(body.olderThanDays)
    let dryRun = body.dryRun ?? true
    let now = Date()
    let cutoff = RetentionComputation.cutoff(now: now, olderThanDays: olderThanDays)
    let cutoffISO = RetentionComputation.cutoffString(cutoff)

    let candidateRows = try await sql.raw("""
        SELECT COUNT(*)::int AS count
        FROM quests
        WHERE (
            deleted_at IS NOT NULL
            AND deleted_at <= \(bind: cutoff)
        ) OR (
            deleted_at IS NULL
            AND status IN ('DONE', 'ARCHIVED')
            AND terminal_since_at IS NOT NULL
            AND terminal_since_at <= \(bind: cutoff)
        )
        """).all()
    let candidateCount: Int = try candidateRows.first?.decode(column: "count", as: Int.self) ?? 0

    var deletedCount = 0
    if !dryRun && candidateCount > 0 {
        let deletedRows = try await sql.raw("""
            DELETE FROM quests
            WHERE id IN (
                SELECT id
                FROM quests
                WHERE (
                    deleted_at IS NOT NULL
                    AND deleted_at <= \(bind: cutoff)
                ) OR (
                    deleted_at IS NULL
                    AND status IN ('DONE', 'ARCHIVED')
                    AND terminal_since_at IS NOT NULL
                    AND terminal_since_at <= \(bind: cutoff)
                )
            )
            RETURNING id
            """).all()
        deletedCount = deletedRows.count
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: dryRun ? "retention.quests.dry_run" : "retention.quests.execute",
        entityType: "quest",
        details: "olderThanDays=\(olderThanDays),candidateCount=\(candidateCount),deletedCount=\(deletedCount)"
    )

    return .init(
        dryRun: dryRun,
        olderThanDays: olderThanDays,
        cutoff: cutoffISO,
        candidateCount: candidateCount,
        deletedCount: deletedCount
    )
}
