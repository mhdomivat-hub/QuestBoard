import Vapor
import Fluent
import SQLKit

private let terminalQuestStatuses: Set<String> = [Quest.Status.done.rawValue, Quest.Status.archived.rawValue]

private func questFromRow(_ row: SQLRow) throws -> QuestResponseDTO {
    let id: UUID = try row.decode(column: "id", as: UUID.self)
    let title: String = try row.decode(column: "title", as: String.self)
    let description: String = try row.decode(column: "description", as: String.self)
    let status: String = try row.decode(column: "status", as: String.self)
    let createdAt: Date? = try row.decodeNil(column: "created_at") ? nil : row.decode(column: "created_at", as: Date.self)
    let createdByUserId: UUID? = try row.decodeNil(column: "created_by_user_id") ? nil : row.decode(column: "created_by_user_id", as: UUID.self)
    let createdByUsername: String? = try? row.decode(column: "created_by_username", as: String.self)
    let isApproved: Bool = try row.decode(column: "is_approved", as: Bool.self)
    let approvedAt: Date? = try row.decodeNil(column: "approved_at") ? nil : row.decode(column: "approved_at", as: Date.self)
    return .init(
        id: id,
        title: title,
        description: description,
        status: status,
        createdAt: createdAt,
        createdByUserId: createdByUserId,
        createdByUsername: createdByUsername,
        isApproved: isApproved,
        approvedAt: approvedAt
    )
}

private func normalizedQuestStatus(_ raw: String?) throws -> String {
    let status = (raw ?? Quest.Status.open.rawValue).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard Quest.allowedStatuses.contains(status) else {
        throw Abort(.badRequest, reason: "invalid status")
    }
    return status
}

func listQuests(_ req: Request) async throws -> [QuestResponseDTO] {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }
    guard let actorId = actor.id else {
        throw Abort(.internalServerError, reason: "user id missing")
    }

    let requestedLimit = req.query[Int.self, at: "limit"] ?? 100
    let limit = max(1, min(requestedLimit, 500))
    let requestedOffset = req.query[Int.self, at: "offset"] ?? 0
    let offset = max(0, requestedOffset)

    let rows: [SQLRow]
    if isAdminRole(actor.role) {
        rows = try await sql.raw("""
            SELECT q.id, q.title, q.description, q.status, q.created_at, q.created_by_user_id, q.is_approved, q.approved_at, u.username AS created_by_username
            FROM quests q
            LEFT JOIN users u ON u.id = q.created_by_user_id
            ORDER BY title ASC
            LIMIT \(bind: limit)
            OFFSET \(bind: offset)
            """).all()
    } else {
        rows = try await sql.raw("""
            SELECT q.id, q.title, q.description, q.status, q.created_at, q.created_by_user_id, q.is_approved, q.approved_at, u.username AS created_by_username
            FROM quests q
            LEFT JOIN users u ON u.id = q.created_by_user_id
            WHERE q.is_approved = TRUE OR q.created_by_user_id = \(bind: actorId)
            ORDER BY title ASC
            LIMIT \(bind: limit)
            OFFSET \(bind: offset)
            """).all()
    }
    return try rows.map(questFromRow)
}

func getQuest(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    guard let questID = req.parameters.get("questID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        throw Abort(.notFound)
    }
    guard canReadQuest(user: actor, quest: questAccess) else {
        throw Abort(.notFound)
    }

    let rows = try await sql.raw("""
        SELECT q.id, q.title, q.description, q.status, q.created_at, q.created_by_user_id, q.is_approved, q.approved_at, u.username AS created_by_username
        FROM quests q
        LEFT JOIN users u ON u.id = q.created_by_user_id
        WHERE q.id = \(bind: questID)
        LIMIT 1
        """).all()
    guard let row = rows.first else { throw Abort(.notFound) }
    return try questFromRow(row)
}

func createQuest(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }
    guard let actorId = actor.id else {
        throw Abort(.internalServerError, reason: "user id missing")
    }

    let body = try req.content.decode(QuestCreateDTO.self)
    guard !body.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "title is required")
    }

    let status = try normalizedQuestStatus(body.status)
    let id = UUID()
    let terminalSinceAt: Date? = terminalQuestStatuses.contains(status) ? Date() : nil
    let isApproved = isAdminRole(actor.role)
    let approvedAt: Date? = isApproved ? Date() : nil
    let approvedByUserId: UUID? = isApproved ? actorId : nil

    try await sql.raw("""
        INSERT INTO quests (id, title, description, status, terminal_since_at, deleted_at, created_by_user_id, is_approved, approved_at, approved_by_user_id)
        VALUES (\(bind: id), \(bind: body.title), \(bind: body.description), \(bind: status), \(bind: terminalSinceAt), NULL, \(bind: actorId), \(bind: isApproved), \(bind: approvedAt), \(bind: approvedByUserId))
        """).run()

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "quest.create",
        entityType: "quest",
        entityId: id,
        details: "status=\(status),approved=\(isApproved)"
    )

    return .init(
        id: id,
        title: body.title,
        description: body.description,
        status: status,
        createdAt: nil,
        createdByUserId: actorId,
        createdByUsername: actor.username,
        isApproved: isApproved,
        approvedAt: approvedAt
    )
}

func updateQuestStatus(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    guard let questID = req.parameters.get("questID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        throw Abort(.notFound)
    }
    guard canEditQuest(user: actor, quest: questAccess) else {
        throw Abort(.forbidden)
    }

    let body = try req.content.decode(QuestStatusUpdateDTO.self)
    let status = try normalizedQuestStatus(body.status)
    let terminalSinceAt: Date? = terminalQuestStatuses.contains(status) ? Date() : nil

    let rows: [SQLRow] = try await sql.raw("""
        UPDATE quests
        SET status = \(bind: status),
            terminal_since_at = \(bind: terminalSinceAt)
        WHERE id = \(bind: questID)
        RETURNING id, title, description, status, created_at, created_by_user_id, is_approved, approved_at
        """).all()
    if rows.isEmpty {
        throw Abort(.notFound)
    }

    guard let row = rows.first else { throw Abort(.notFound) }
    let response = try questFromRow(row)
    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "quest.status.update",
        entityType: "quest",
        entityId: response.id,
        details: "status=\(response.status)"
    )
    return response
}

func markQuestDeleted(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    guard let questID = req.parameters.get("questID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        throw Abort(.notFound)
    }
    guard canEditQuest(user: actor, quest: questAccess) else {
        throw Abort(.forbidden)
    }

    let now = Date()
    let rows: [SQLRow] = try await sql.raw("""
        UPDATE quests
        SET deleted_at = \(bind: now),
            terminal_since_at = COALESCE(terminal_since_at, \(bind: now))
        WHERE id = \(bind: questID)
        RETURNING id, title, description, status, created_at, created_by_user_id, is_approved, approved_at
        """).all()
    guard let row = rows.first else {
        throw Abort(.notFound)
    }
    let response = try questFromRow(row)
    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "quest.delete.soft",
        entityType: "quest",
        entityId: response.id
    )
    return response
}

func restoreQuest(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    guard let questID = req.parameters.get("questID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        throw Abort(.notFound)
    }
    guard canEditQuest(user: actor, quest: questAccess) else {
        throw Abort(.forbidden)
    }

    let rows: [SQLRow] = try await sql.raw("""
        UPDATE quests
        SET deleted_at = NULL
        WHERE id = \(bind: questID)
        RETURNING id, title, description, status, created_at, created_by_user_id, is_approved, approved_at
        """).all()
    guard let row = rows.first else {
        throw Abort(.notFound)
    }
    let response = try questFromRow(row)
    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "quest.restore",
        entityType: "quest",
        entityId: response.id
    )
    return response
}

func approveQuest(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }
    guard let actorId = actor.id else {
        throw Abort(.internalServerError, reason: "user id missing")
    }
    guard let questID = req.parameters.get("questID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    let now = Date()
    let rows: [SQLRow] = try await sql.raw("""
        UPDATE quests
        SET is_approved = TRUE,
            approved_at = \(bind: now),
            approved_by_user_id = \(bind: actorId)
        WHERE id = \(bind: questID)
        RETURNING id, title, description, status, created_at, created_by_user_id, is_approved, approved_at
        """).all()
    guard let row = rows.first else {
        throw Abort(.notFound)
    }
    let response = try questFromRow(row)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "quest.approve",
        entityType: "quest",
        entityId: response.id
    )

    return response
}
