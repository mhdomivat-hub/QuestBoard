import Vapor
import SQLKit

private let contributionAllowedStatuses: Set<String> = ["CLAIMED", "COLLECTED", "DELIVERED", "CANCELLED"]

private func normalizedContributionStatus(_ raw: String?) throws -> String {
    let status = (raw ?? "CLAIMED").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard contributionAllowedStatuses.contains(status) else {
        throw Abort(.badRequest, reason: "invalid contribution status")
    }
    return status
}

private func requirementFromRow(_ row: SQLRow) throws -> RequirementResponseDTO {
    let id: UUID = try row.decode(column: "id", as: UUID.self)
    let questId: UUID = try row.decode(column: "quest_id", as: UUID.self)
    let itemName: String = try row.decode(column: "item_name", as: String.self)
    let qtyNeeded: Int = try row.decode(column: "qty_needed", as: Int.self)
    let unit: String = try row.decode(column: "unit", as: String.self)
    let collectedQty: Int = try row.decode(column: "collected_qty", as: Int.self)
    let deliveredQty: Int = try row.decode(column: "delivered_qty", as: Int.self)
    let openQty = max(qtyNeeded - deliveredQty, 0)
    let excessQty = max(deliveredQty - qtyNeeded, 0)

    return .init(
        id: id,
        questId: questId,
        itemName: itemName,
        qtyNeeded: qtyNeeded,
        unit: unit,
        collectedQty: collectedQty,
        deliveredQty: deliveredQty,
        openQty: openQty,
        excessQty: excessQty
    )
}

private func contributionFromRow(_ row: SQLRow) throws -> ContributionResponseDTO {
    let id: UUID = try row.decode(column: "id", as: UUID.self)
    let requirementId: UUID = try row.decode(column: "requirement_id", as: UUID.self)
    let userId: UUID = try row.decode(column: "user_id", as: UUID.self)
    let username: String = try row.decode(column: "username", as: String.self)
    let qty: Int = try row.decode(column: "qty", as: Int.self)
    let status: String = try row.decode(column: "status", as: String.self)
    let note: String? = try row.decodeNil(column: "note") ? nil : row.decode(column: "note", as: String.self)

    return .init(
        id: id,
        requirementId: requirementId,
        userId: userId,
        username: username,
        qty: qty,
        status: status,
        note: note
    )
}

private func updateContributionInternal(
    req: Request,
    contributionID: UUID,
    qty: Int?,
    statusRaw: String?,
    note: String?,
    noteProvided: Bool
) async throws -> ContributionResponseDTO {
    let user = try requireAuthenticatedUser(req)
    if user.role == .guest {
        throw Abort(.forbidden, reason: "guest users are read-only")
    }
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }
    guard let currentUserID = user.id else {
        throw Abort(.internalServerError, reason: "user id missing")
    }

    let existingRows = try await sql.raw("""
        SELECT c.id, c.requirement_id, c.user_id, c.qty, c.status, c.note, r.quest_id, q.created_by_user_id AS quest_created_by_user_id
        FROM contributions c
        JOIN requirements r ON r.id = c.requirement_id
        JOIN quests q ON q.id = r.quest_id
        WHERE c.id = \(bind: contributionID)
        LIMIT 1
        """).all()
    guard let existing = existingRows.first else {
        throw Abort(.notFound)
    }

    let requirementId: UUID = try existing.decode(column: "requirement_id", as: UUID.self)
    let ownerUserId: UUID = try existing.decode(column: "user_id", as: UUID.self)
    let existingQty: Int = try existing.decode(column: "qty", as: Int.self)
    let existingStatus: String = try existing.decode(column: "status", as: String.self)
    let existingNote: String? = try existing.decodeNil(column: "note") ? nil : existing.decode(column: "note", as: String.self)
    let questID: UUID = try existing.decode(column: "quest_id", as: UUID.self)
    let questCreatedByUserId: UUID? = try existing.decodeNil(column: "quest_created_by_user_id")
        ? nil
        : existing.decode(column: "quest_created_by_user_id", as: UUID.self)

    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID), canReadQuest(user: user, quest: questAccess) else {
        throw Abort(.notFound)
    }

    if existingStatus == "DELIVERED" {
        throw Abort(.forbidden, reason: "delivered contribution cannot be edited")
    }

    let newStatus = try normalizedContributionStatus(statusRaw ?? existingStatus)
    let newQty = qty ?? existingQty
    let newNote = noteProvided ? note : existingNote
    guard newQty > 0 else {
        throw Abort(.badRequest, reason: "qty must be > 0")
    }

    let isAdmin = user.role == .admin || user.role == .superAdmin
    let isQuestCreator = (questCreatedByUserId == currentUserID)
    let isOwner = (ownerUserId == currentUserID)

    if newStatus == "DELIVERED" {
        guard isAdmin || isQuestCreator else {
            throw Abort(.forbidden, reason: "only quest creator or admin can mark delivered")
        }
    } else {
        guard isOwner else {
            throw Abort(.forbidden, reason: "can only edit own contribution")
        }
    }

    let rows = try await sql.raw("""
        UPDATE contributions
        SET qty = \(bind: newQty),
            status = \(bind: newStatus)::contribution_status,
            note = \(bind: newNote)
        WHERE id = \(bind: contributionID)
        RETURNING id, requirement_id, user_id, qty, status, note
        """).all()
    guard let updated = rows.first else {
        throw Abort(.notFound)
    }

    let updatedUserId: UUID = try updated.decode(column: "user_id", as: UUID.self)
    let userRows = try await sql.raw("SELECT username FROM users WHERE id = \(bind: updatedUserId) LIMIT 1").all()
    guard let userRow = userRows.first else {
        throw Abort(.internalServerError, reason: "user for contribution not found")
    }
    let username: String = try userRow.decode(column: "username", as: String.self)

    let id: UUID = try updated.decode(column: "id", as: UUID.self)
    let qtyResponse: Int = try updated.decode(column: "qty", as: Int.self)
    let statusResponse: String = try updated.decode(column: "status", as: String.self)
    let noteResponse: String? = try updated.decodeNil(column: "note") ? nil : updated.decode(column: "note", as: String.self)

    return .init(
        id: id,
        requirementId: requirementId,
        userId: updatedUserId,
        username: username,
        qty: qtyResponse,
        status: statusResponse,
        note: noteResponse
    )
}

func listRequirementsForQuest(_ req: Request) async throws -> [RequirementResponseDTO] {
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

    let requestedLimit = req.query[Int.self, at: "limit"] ?? 200
    let limit = max(1, min(requestedLimit, 500))
    let requestedOffset = req.query[Int.self, at: "offset"] ?? 0
    let offset = max(0, requestedOffset)

    let rows = try await sql.raw("""
        SELECT
            r.id,
            r.quest_id,
            r.item_name,
            r.qty_needed,
            r.unit,
            COALESCE(SUM(CASE WHEN c.status IN ('COLLECTED','DELIVERED') THEN c.qty ELSE 0 END), 0)::int AS collected_qty,
            COALESCE(SUM(CASE WHEN c.status = 'DELIVERED' THEN c.qty ELSE 0 END), 0)::int AS delivered_qty
        FROM requirements r
        LEFT JOIN contributions c ON c.requirement_id = r.id
        WHERE r.quest_id = \(bind: questID)
        GROUP BY r.id, r.quest_id, r.item_name, r.qty_needed, r.unit
        ORDER BY r.item_name ASC
        LIMIT \(bind: limit)
        OFFSET \(bind: offset)
        """).all()

    return try rows.map(requirementFromRow)
}

func createRequirement(_ req: Request) async throws -> RequirementResponseDTO {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    guard let questID = req.parameters.get("questID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        throw Abort(.notFound, reason: "quest not found")
    }
    guard canEditQuest(user: actor, quest: questAccess) else {
        throw Abort(.forbidden)
    }

    let body = try req.content.decode(RequirementCreateDTO.self)
    guard !body.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw Abort(.badRequest, reason: "itemName is required")
    }
    guard body.qtyNeeded > 0 else {
        throw Abort(.badRequest, reason: "qtyNeeded must be > 0")
    }

    let questRows = try await sql.raw("SELECT id FROM quests WHERE id = \(bind: questID) LIMIT 1").all()
    guard !questRows.isEmpty else {
        throw Abort(.notFound, reason: "quest not found")
    }

    let id = UUID()
    try await sql.raw("""
        INSERT INTO requirements (id, quest_id, item_name, qty_needed, unit)
        VALUES (\(bind: id), \(bind: questID), \(bind: body.itemName), \(bind: body.qtyNeeded), \(bind: body.unit))
        """).run()

    return .init(
        id: id,
        questId: questID,
        itemName: body.itemName,
        qtyNeeded: body.qtyNeeded,
        unit: body.unit,
        collectedQty: 0,
        deliveredQty: 0,
        openQty: body.qtyNeeded,
        excessQty: 0
    )
}

func listContributionsForRequirement(_ req: Request) async throws -> [ContributionResponseDTO] {
    let actor = try requireAuthenticatedUser(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }
    let requestedLimit = req.query[Int.self, at: "limit"] ?? 200
    let limit = max(1, min(requestedLimit, 500))
    let requestedOffset = req.query[Int.self, at: "offset"] ?? 0
    let offset = max(0, requestedOffset)

    guard let requirementID = req.parameters.get("requirementID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    let requirementRows = try await sql.raw("""
        SELECT quest_id
        FROM requirements
        WHERE id = \(bind: requirementID)
        LIMIT 1
        """).all()
    guard let requirementRow = requirementRows.first else {
        return []
    }
    let questID: UUID = try requirementRow.decode(column: "quest_id", as: UUID.self)
    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        return []
    }
    guard canReadQuest(user: actor, quest: questAccess) else {
        return []
    }

    let rows = try await sql.raw("""
        SELECT c.id, c.requirement_id, c.user_id, u.username, c.qty, c.status, c.note
        FROM contributions c
        JOIN users u ON u.id = c.user_id
        WHERE c.requirement_id = \(bind: requirementID)
        ORDER BY c.created_at DESC NULLS LAST
        LIMIT \(bind: limit)
        OFFSET \(bind: offset)
        """).all()

    return try rows.map(contributionFromRow)
}

func createContribution(_ req: Request) async throws -> ContributionResponseDTO {
    let user = try requireAuthenticatedUser(req)
    if user.role == .guest {
        throw Abort(.forbidden, reason: "guest users are read-only")
    }
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    guard let userID = user.id else {
        throw Abort(.internalServerError, reason: "user id missing")
    }

    guard let requirementID = req.parameters.get("requirementID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    let body = try req.content.decode(ContributionCreateDTO.self)
    guard body.qty > 0 else {
        throw Abort(.badRequest, reason: "qty must be > 0")
    }
    let status = try normalizedContributionStatus(body.status)

    let reqRows = try await sql.raw("""
        SELECT r.id, r.quest_id
        FROM requirements r
        WHERE r.id = \(bind: requirementID)
        LIMIT 1
        """).all()
    guard let requirementRow = reqRows.first else {
        throw Abort(.notFound, reason: "requirement not found")
    }
    let questID: UUID = try requirementRow.decode(column: "quest_id", as: UUID.self)
    guard let questAccess = try await loadQuestAccessContext(sql: sql, questID: questID) else {
        throw Abort(.notFound, reason: "quest not found")
    }
    guard canReadQuest(user: user, quest: questAccess) else {
        throw Abort(.notFound, reason: "requirement not found")
    }

    let id = UUID()
    try await sql.raw("""
        INSERT INTO contributions (id, requirement_id, user_id, qty, status, note)
        VALUES (\(bind: id), \(bind: requirementID), \(bind: userID), \(bind: body.qty), \(bind: status)::contribution_status, \(bind: body.note))
        """).run()

    return .init(
        id: id,
        requirementId: requirementID,
        userId: userID,
        username: user.username,
        qty: body.qty,
        status: status,
        note: body.note
    )
}

func updateContributionStatus(_ req: Request) async throws -> ContributionResponseDTO {
    guard let contributionID = req.parameters.get("contributionID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    let body = try req.content.decode(ContributionStatusUpdateDTO.self)
    return try await updateContributionInternal(
        req: req,
        contributionID: contributionID,
        qty: nil,
        statusRaw: body.status,
        note: nil,
        noteProvided: false
    )
}

func updateContribution(_ req: Request) async throws -> ContributionResponseDTO {
    guard let contributionID = req.parameters.get("contributionID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    let body = try req.content.decode(ContributionUpdateDTO.self)
    return try await updateContributionInternal(
        req: req,
        contributionID: contributionID,
        qty: body.qty,
        statusRaw: body.status,
        note: body.note,
        noteProvided: true
    )
}
