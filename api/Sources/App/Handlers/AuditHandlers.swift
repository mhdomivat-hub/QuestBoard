import Vapor
import Fluent

func listAuditEvents(_ req: Request) async throws -> [AuditEventResponseDTO] {
    _ = try requireAdminOrSuperAdmin(req)

    let requestedLimit = req.query[Int.self, at: "limit"] ?? 100
    let limit = max(1, min(requestedLimit, 500))
    let requestedOffset = req.query[Int.self, at: "offset"] ?? 0
    let offset = max(0, requestedOffset)

    let rows = try await AuditEvent.query(on: req.db)
        .sort(\.$createdAt, .descending)
        .limit(limit)
        .offset(offset)
        .all()

    return rows.compactMap { row in
        guard let id = row.id else { return nil }
        return .init(
            id: id,
            actorUsername: row.actorUsername,
            action: row.action,
            entityType: row.entityType,
            entityId: row.entityId,
            details: row.details,
            createdAt: row.createdAt
        )
    }
}
