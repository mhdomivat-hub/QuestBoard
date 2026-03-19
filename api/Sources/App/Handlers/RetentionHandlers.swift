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

enum RetentionCleanupTarget: String, CaseIterable {
    case questContributions = "QUEST_CONTRIBUTIONS"
    case blueprintCrafters = "BLUEPRINT_CRAFTERS"
    case storageEntries = "STORAGE_ENTRIES"
    case invites = "INVITES"
    case passwordResets = "PASSWORD_RESETS"
    case usernameChangeRequests = "USERNAME_CHANGE_REQUESTS"

    var label: String {
        switch self {
        case .questContributions:
            return "Quest Contributions"
        case .blueprintCrafters:
            return "Blueprint Crafter-Zuordnungen"
        case .storageEntries:
            return "Storage Eintraege"
        case .invites:
            return "Invites"
        case .passwordResets:
            return "Password Reset Requests + Tokens"
        case .usernameChangeRequests:
            return "Username Change Requests"
        }
    }

    func count(sql: SQLDatabase) async throws -> Int {
        let query: String
        switch self {
        case .questContributions:
            query = "SELECT COUNT(*)::int AS c FROM contributions"
        case .blueprintCrafters:
            query = "SELECT COUNT(*)::int AS c FROM blueprint_crafters"
        case .storageEntries:
            query = "SELECT COUNT(*)::int AS c FROM storage_entries"
        case .invites:
            query = "SELECT COUNT(*)::int AS c FROM invites"
        case .passwordResets:
            query = """
                SELECT (
                    (SELECT COUNT(*) FROM password_reset_requests) +
                    (SELECT COUNT(*) FROM password_reset_tokens)
                )::int AS c
                """
        case .usernameChangeRequests:
            query = "SELECT COUNT(*)::int AS c FROM username_change_requests"
        }

        let rows = try await sql.raw("\(unsafeRaw: query)").all()
        return try rows.first?.decode(column: "c", as: Int.self) ?? 0
    }

    func delete(sql: SQLDatabase) async throws -> Int {
        switch self {
        case .questContributions:
            let rows = try await sql.raw("DELETE FROM contributions RETURNING id").all()
            return rows.count
        case .blueprintCrafters:
            let rows = try await sql.raw("DELETE FROM blueprint_crafters RETURNING blueprint_id").all()
            return rows.count
        case .storageEntries:
            let rows = try await sql.raw("DELETE FROM storage_entries RETURNING id").all()
            return rows.count
        case .invites:
            let rows = try await sql.raw("DELETE FROM invites RETURNING id").all()
            return rows.count
        case .passwordResets:
            let tokenRows = try await sql.raw("DELETE FROM password_reset_tokens RETURNING id").all()
            let requestRows = try await sql.raw("DELETE FROM password_reset_requests RETURNING id").all()
            return tokenRows.count + requestRows.count
        case .usernameChangeRequests:
            let rows = try await sql.raw("DELETE FROM username_change_requests RETURNING id").all()
            return rows.count
        }
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

func cleanupSelectedData(_ req: Request) async throws -> RetentionSelectionCleanupResponseDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let body = try req.content.decode(RetentionSelectionCleanupRequestDTO.self)
    let dryRun = body.dryRun ?? true

    let requestedTargets = Array(Set(body.targets.compactMap { RetentionCleanupTarget(rawValue: $0.uppercased()) }))
        .sorted { $0.rawValue < $1.rawValue }
    guard !requestedTargets.isEmpty else {
        throw Abort(.badRequest, reason: "At least one cleanup target is required")
    }

    let requiresSuperAdmin = requestedTargets.contains(.blueprintCrafters) || requestedTargets.contains(.storageEntries)
    if requiresSuperAdmin, actor.role != .superAdmin {
        throw Abort(.forbidden, reason: "Only super admins may wipe blueprint crafters or storage entries")
    }

    var results: [RetentionSelectionCleanupTargetResultDTO] = []
    var totalCandidateCount = 0
    var totalDeletedCount = 0

    for target in requestedTargets {
        let candidateCount = try await target.count(sql: sql)
        let deletedCount = dryRun ? 0 : try await target.delete(sql: sql)
        totalCandidateCount += candidateCount
        totalDeletedCount += deletedCount
        results.append(
            .init(
                key: target.rawValue,
                label: target.label,
                candidateCount: candidateCount,
                deletedCount: deletedCount
            )
        )
    }

    let summary = requestedTargets.map { $0.rawValue }.joined(separator: ",")
    await recordAuditEvent(
        on: req,
        actor: actor,
        action: dryRun ? "retention.selected.dry_run" : "retention.selected.execute",
        entityType: "system",
        details: "targets=\(summary),candidateCount=\(totalCandidateCount),deletedCount=\(totalDeletedCount)"
    )

    return .init(
        dryRun: dryRun,
        targets: results,
        totalCandidateCount: totalCandidateCount,
        totalDeletedCount: totalDeletedCount
    )
}
