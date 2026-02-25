import Vapor
import SQLKit

private let importContributionAllowedStatuses: Set<String> = ["CLAIMED", "COLLECTED", "DELIVERED", "CANCELLED"]

private func sqlRecordExists(sql: SQLDatabase, table: String, id: UUID) async throws -> Bool {
    let rows = try await sql.raw("SELECT 1 FROM \(raw: table) WHERE id = \(bind: id) LIMIT 1").all()
    return !rows.isEmpty
}

private func sqlUserExistsByUsername(sql: SQLDatabase, username: String) async throws -> Bool {
    let rows = try await sql.raw("SELECT 1 FROM users WHERE username = \(bind: username) LIMIT 1").all()
    return !rows.isEmpty
}

private func sqlTokenHashExists(sql: SQLDatabase, table: String, tokenHash: String) async throws -> Bool {
    let rows = try await sql.raw("SELECT 1 FROM \(raw: table) WHERE token_hash = \(bind: tokenHash) LIMIT 1").all()
    return !rows.isEmpty
}

private func decodeOptionalUUID(_ row: SQLRow, column: String) throws -> UUID? {
    try row.decodeNil(column: column) ? nil : row.decode(column: column, as: UUID.self)
}

private func decodeOptionalDate(_ row: SQLRow, column: String) throws -> Date? {
    try row.decodeNil(column: column) ? nil : row.decode(column: column, as: Date.self)
}

private func decodeOptionalString(_ row: SQLRow, column: String) throws -> String? {
    try row.decodeNil(column: column) ? nil : row.decode(column: column, as: String.self)
}

func exportAllData(_ req: Request) async throws -> AdminDataExportDTO {
    let actor = try requireSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let userRows = try await sql.raw("SELECT id, username, password_hash, role FROM users ORDER BY username ASC").all()
    let questRows = try await sql.raw("""
        SELECT id, title, description, status, terminal_since_at, deleted_at, created_at, created_by_user_id, is_approved, approved_at, approved_by_user_id
        FROM quests
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let requirementRows = try await sql.raw("SELECT id, quest_id, item_name, qty_needed, unit FROM requirements ORDER BY item_name ASC, id ASC").all()
    let contributionRows = try await sql.raw("""
        SELECT id, requirement_id, user_id, qty, status, note, created_at
        FROM contributions
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let requestRows = try await sql.raw("""
        SELECT id, user_id, status, approved_by, note, approved_at, created_at
        FROM password_reset_requests
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let resetTokenRows = try await sql.raw("""
        SELECT id, request_id, token_hash, expires_at, used_at, created_at
        FROM password_reset_tokens
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let apiTokenRows = try await sql.raw("""
        SELECT id, user_id, token_hash, expires_at, created_at
        FROM api_tokens
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let auditRows = try await sql.raw("""
        SELECT id, actor_user_id, actor_username, action, entity_type, entity_id, details, created_at
        FROM audit_events
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()

    await recordAuditEvent(on: req, actor: actor, action: "admin.data.export", entityType: "system")

    return .init(
        version: 1,
        generatedAt: Date(),
        users: try userRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                username: try $0.decode(column: "username", as: String.self),
                passwordHash: try $0.decode(column: "password_hash", as: String.self),
                role: try $0.decode(column: "role", as: String.self)
            )
        },
        quests: try questRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                title: try $0.decode(column: "title", as: String.self),
                description: try $0.decode(column: "description", as: String.self),
                status: try $0.decode(column: "status", as: String.self),
                terminalSinceAt: try decodeOptionalDate($0, column: "terminal_since_at"),
                deletedAt: try decodeOptionalDate($0, column: "deleted_at"),
                createdAt: try decodeOptionalDate($0, column: "created_at"),
                createdByUserId: try decodeOptionalUUID($0, column: "created_by_user_id"),
                isApproved: try $0.decode(column: "is_approved", as: Bool.self),
                approvedAt: try decodeOptionalDate($0, column: "approved_at"),
                approvedByUserId: try decodeOptionalUUID($0, column: "approved_by_user_id")
            )
        },
        requirements: try requirementRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                questId: try $0.decode(column: "quest_id", as: UUID.self),
                itemName: try $0.decode(column: "item_name", as: String.self),
                qtyNeeded: try $0.decode(column: "qty_needed", as: Int.self),
                unit: try $0.decode(column: "unit", as: String.self)
            )
        },
        contributions: try contributionRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                requirementId: try $0.decode(column: "requirement_id", as: UUID.self),
                userId: try $0.decode(column: "user_id", as: UUID.self),
                qty: try $0.decode(column: "qty", as: Int.self),
                status: try $0.decode(column: "status", as: String.self),
                note: try decodeOptionalString($0, column: "note"),
                createdAt: try decodeOptionalDate($0, column: "created_at")
            )
        },
        passwordResetRequests: try requestRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                userId: try $0.decode(column: "user_id", as: UUID.self),
                status: try $0.decode(column: "status", as: String.self),
                approvedBy: try decodeOptionalUUID($0, column: "approved_by"),
                note: try decodeOptionalString($0, column: "note"),
                approvedAt: try decodeOptionalDate($0, column: "approved_at"),
                createdAt: try decodeOptionalDate($0, column: "created_at")
            )
        },
        passwordResetTokens: try resetTokenRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                requestId: try $0.decode(column: "request_id", as: UUID.self),
                tokenHash: try $0.decode(column: "token_hash", as: String.self),
                expiresAt: try $0.decode(column: "expires_at", as: Date.self),
                usedAt: try decodeOptionalDate($0, column: "used_at"),
                createdAt: try decodeOptionalDate($0, column: "created_at")
            )
        },
        apiTokens: try apiTokenRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                userId: try $0.decode(column: "user_id", as: UUID.self),
                tokenHash: try $0.decode(column: "token_hash", as: String.self),
                expiresAt: try $0.decode(column: "expires_at", as: Date.self),
                createdAt: try decodeOptionalDate($0, column: "created_at")
            )
        },
        auditEvents: try auditRows.map {
            .init(
                id: try $0.decode(column: "id", as: UUID.self),
                actorUserId: try decodeOptionalUUID($0, column: "actor_user_id"),
                actorUsername: try $0.decode(column: "actor_username", as: String.self),
                action: try $0.decode(column: "action", as: String.self),
                entityType: try $0.decode(column: "entity_type", as: String.self),
                entityId: try decodeOptionalUUID($0, column: "entity_id"),
                details: try decodeOptionalString($0, column: "details"),
                createdAt: try decodeOptionalDate($0, column: "created_at")
            )
        }
    )
}

private func makeEmptyExport(version: Int = 1, generatedAt: Date = Date()) -> AdminDataExportDTO {
    .init(
        version: version,
        generatedAt: generatedAt,
        users: [],
        quests: [],
        requirements: [],
        contributions: [],
        passwordResetRequests: [],
        passwordResetTokens: [],
        apiTokens: [],
        auditEvents: []
    )
}

private func parseLimit(_ req: Request) -> Int {
    let requested = (try? req.query.get(Int.self, at: "limit")) ?? 1000
    return max(1, min(2000, requested))
}

private func parseOffset(_ req: Request) -> Int {
    let requested = (try? req.query.get(Int.self, at: "offset")) ?? 0
    return max(0, requested)
}

private func countAllRows(sql: SQLDatabase, table: String) async throws -> Int {
    let rows = try await sql.raw("SELECT COUNT(*) AS c FROM \(unsafeRaw: table)").all()
    guard let row = rows.first else { return 0 }
    return try row.decode(column: "c", as: Int.self)
}

func exportDataManifest(_ req: Request) async throws -> AdminDataExportManifestDTO {
    let _ = try requireSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    return .init(
        version: 1,
        generatedAt: Date(),
        counts: .init(
            users: try await countAllRows(sql: sql, table: "users"),
            quests: try await countAllRows(sql: sql, table: "quests"),
            requirements: try await countAllRows(sql: sql, table: "requirements"),
            contributions: try await countAllRows(sql: sql, table: "contributions"),
            passwordResetRequests: try await countAllRows(sql: sql, table: "password_reset_requests"),
            passwordResetTokens: try await countAllRows(sql: sql, table: "password_reset_tokens"),
            apiTokens: try await countAllRows(sql: sql, table: "api_tokens"),
            auditEvents: try await countAllRows(sql: sql, table: "audit_events")
        )
    )
}

func exportDataSection(_ req: Request) async throws -> AdminDataExportDTO {
    let _ = try requireSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let section = (try req.parameters.require("section")).lowercased()
    let limit = parseLimit(req)
    let offset = parseOffset(req)
    let generatedAt = Date()
    var result = makeEmptyExport(generatedAt: generatedAt)

    switch section {
    case "users":
        let rows = try await sql.raw("""
            SELECT id, username, password_hash, role
            FROM users
            ORDER BY username ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    username: try $0.decode(column: "username", as: String.self),
                    passwordHash: try $0.decode(column: "password_hash", as: String.self),
                    role: try $0.decode(column: "role", as: String.self)
                )
            },
            quests: [],
            requirements: [],
            contributions: [],
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "quests":
        let rows = try await sql.raw("""
            SELECT id, title, description, status, terminal_since_at, deleted_at, created_at, created_by_user_id, is_approved, approved_at, approved_by_user_id
            FROM quests
            ORDER BY created_at ASC NULLS LAST, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    title: try $0.decode(column: "title", as: String.self),
                    description: try $0.decode(column: "description", as: String.self),
                    status: try $0.decode(column: "status", as: String.self),
                    terminalSinceAt: try decodeOptionalDate($0, column: "terminal_since_at"),
                    deletedAt: try decodeOptionalDate($0, column: "deleted_at"),
                    createdAt: try decodeOptionalDate($0, column: "created_at"),
                    createdByUserId: try decodeOptionalUUID($0, column: "created_by_user_id"),
                    isApproved: try $0.decode(column: "is_approved", as: Bool.self),
                    approvedAt: try decodeOptionalDate($0, column: "approved_at"),
                    approvedByUserId: try decodeOptionalUUID($0, column: "approved_by_user_id")
                )
            },
            requirements: [],
            contributions: [],
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "requirements":
        let rows = try await sql.raw("""
            SELECT id, quest_id, item_name, qty_needed, unit
            FROM requirements
            ORDER BY item_name ASC, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    questId: try $0.decode(column: "quest_id", as: UUID.self),
                    itemName: try $0.decode(column: "item_name", as: String.self),
                    qtyNeeded: try $0.decode(column: "qty_needed", as: Int.self),
                    unit: try $0.decode(column: "unit", as: String.self)
                )
            },
            contributions: [],
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "contributions":
        let rows = try await sql.raw("""
            SELECT id, requirement_id, user_id, qty, status, note, created_at
            FROM contributions
            ORDER BY created_at ASC NULLS LAST, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: [],
            contributions: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    requirementId: try $0.decode(column: "requirement_id", as: UUID.self),
                    userId: try $0.decode(column: "user_id", as: UUID.self),
                    qty: try $0.decode(column: "qty", as: Int.self),
                    status: try $0.decode(column: "status", as: String.self),
                    note: try decodeOptionalString($0, column: "note"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "passwordresetrequests":
        let rows = try await sql.raw("""
            SELECT id, user_id, status, approved_by, note, approved_at, created_at
            FROM password_reset_requests
            ORDER BY created_at ASC NULLS LAST, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: [],
            contributions: [],
            passwordResetRequests: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    userId: try $0.decode(column: "user_id", as: UUID.self),
                    status: try $0.decode(column: "status", as: String.self),
                    approvedBy: try decodeOptionalUUID($0, column: "approved_by"),
                    note: try decodeOptionalString($0, column: "note"),
                    approvedAt: try decodeOptionalDate($0, column: "approved_at"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "passwordresettokens":
        let rows = try await sql.raw("""
            SELECT id, request_id, token_hash, expires_at, used_at, created_at
            FROM password_reset_tokens
            ORDER BY created_at ASC NULLS LAST, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: [],
            contributions: [],
            passwordResetRequests: [],
            passwordResetTokens: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    requestId: try $0.decode(column: "request_id", as: UUID.self),
                    tokenHash: try $0.decode(column: "token_hash", as: String.self),
                    expiresAt: try $0.decode(column: "expires_at", as: Date.self),
                    usedAt: try decodeOptionalDate($0, column: "used_at"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            apiTokens: [],
            auditEvents: []
        )
    case "apitokens":
        let rows = try await sql.raw("""
            SELECT id, user_id, token_hash, expires_at, created_at
            FROM api_tokens
            ORDER BY created_at ASC NULLS LAST, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: [],
            contributions: [],
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    userId: try $0.decode(column: "user_id", as: UUID.self),
                    tokenHash: try $0.decode(column: "token_hash", as: String.self),
                    expiresAt: try $0.decode(column: "expires_at", as: Date.self),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            auditEvents: []
        )
    case "auditevents":
        let rows = try await sql.raw("""
            SELECT id, actor_user_id, actor_username, action, entity_type, entity_id, details, created_at
            FROM audit_events
            ORDER BY created_at ASC NULLS LAST, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: [],
            contributions: [],
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    actorUserId: try decodeOptionalUUID($0, column: "actor_user_id"),
                    actorUsername: try $0.decode(column: "actor_username", as: String.self),
                    action: try $0.decode(column: "action", as: String.self),
                    entityType: try $0.decode(column: "entity_type", as: String.self),
                    entityId: try decodeOptionalUUID($0, column: "entity_id"),
                    details: try decodeOptionalString($0, column: "details"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            }
        )
    default:
        throw Abort(.badRequest, reason: "Unknown export section: \(section)")
    }

    return result
}

func importAllData(_ req: Request) async throws -> AdminDataImportResultDTO {
    let actor = try requireSuperAdmin(req)
    let payload = try req.content.decode(AdminDataExportDTO.self)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    var usersInserted = 0
    var usersSkipped = 0
    var questsInserted = 0
    var questsSkipped = 0
    var requirementsInserted = 0
    var requirementsSkipped = 0
    var contributionsInserted = 0
    var contributionsSkipped = 0
    var passwordResetRequestsInserted = 0
    var passwordResetRequestsSkipped = 0
    var passwordResetTokensInserted = 0
    var passwordResetTokensSkipped = 0
    var apiTokensInserted = 0
    var apiTokensSkipped = 0
    var auditEventsInserted = 0
    var auditEventsSkipped = 0

    for item in payload.users {
        let existsById = try await sqlRecordExists(sql: sql, table: "users", id: item.id)
        let existsByUsername = try await sqlUserExistsByUsername(sql: sql, username: item.username)
        if existsById || existsByUsername {
            usersSkipped += 1
            continue
        }
        guard User.Role(rawValue: item.role) != nil else {
            usersSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO users (id, username, password_hash, role)
            VALUES (\(bind: item.id), \(bind: item.username), \(bind: item.passwordHash), \(bind: item.role)::user_role)
            """).run()
        usersInserted += 1
    }

    for item in payload.quests {
        if try await sqlRecordExists(sql: sql, table: "quests", id: item.id) {
            questsSkipped += 1
            continue
        }
        if let creatorID = item.createdByUserId, !(try await sqlRecordExists(sql: sql, table: "users", id: creatorID)) {
            questsSkipped += 1
            continue
        }
        if let approverID = item.approvedByUserId, !(try await sqlRecordExists(sql: sql, table: "users", id: approverID)) {
            questsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO quests (id, title, description, status, terminal_since_at, deleted_at, created_at, created_by_user_id, is_approved, approved_at, approved_by_user_id)
            VALUES (
                \(bind: item.id), \(bind: item.title), \(bind: item.description), \(bind: item.status),
                \(bind: item.terminalSinceAt), \(bind: item.deletedAt), \(bind: item.createdAt), \(bind: item.createdByUserId),
                \(bind: item.isApproved), \(bind: item.approvedAt), \(bind: item.approvedByUserId)
            )
            """).run()
        questsInserted += 1
    }

    for item in payload.requirements {
        if try await sqlRecordExists(sql: sql, table: "requirements", id: item.id) {
            requirementsSkipped += 1
            continue
        }
        let questExists = try await sqlRecordExists(sql: sql, table: "quests", id: item.questId)
        if !questExists {
            requirementsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO requirements (id, quest_id, item_name, qty_needed, unit)
            VALUES (\(bind: item.id), \(bind: item.questId), \(bind: item.itemName), \(bind: item.qtyNeeded), \(bind: item.unit))
            """).run()
        requirementsInserted += 1
    }

    for item in payload.contributions {
        if try await sqlRecordExists(sql: sql, table: "contributions", id: item.id) {
            contributionsSkipped += 1
            continue
        }
        let requirementExists = try await sqlRecordExists(sql: sql, table: "requirements", id: item.requirementId)
        let userExists = try await sqlRecordExists(sql: sql, table: "users", id: item.userId)
        if !requirementExists || !userExists {
            contributionsSkipped += 1
            continue
        }
        if !importContributionAllowedStatuses.contains(item.status) {
            contributionsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO contributions (id, requirement_id, user_id, qty, status, note, created_at)
            VALUES (\(bind: item.id), \(bind: item.requirementId), \(bind: item.userId), \(bind: item.qty), \(bind: item.status)::contribution_status, \(bind: item.note), \(bind: item.createdAt))
            """).run()
        contributionsInserted += 1
    }

    for item in payload.passwordResetRequests {
        if try await sqlRecordExists(sql: sql, table: "password_reset_requests", id: item.id) {
            passwordResetRequestsSkipped += 1
            continue
        }
        let userExists = try await sqlRecordExists(sql: sql, table: "users", id: item.userId)
        if !userExists {
            passwordResetRequestsSkipped += 1
            continue
        }
        if let approvedBy = item.approvedBy {
            let approverExists = try await sqlRecordExists(sql: sql, table: "users", id: approvedBy)
            if !approverExists {
                passwordResetRequestsSkipped += 1
                continue
            }
        }
        guard PasswordResetStatus(rawValue: item.status) != nil else {
            passwordResetRequestsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO password_reset_requests (id, user_id, status, approved_by, note, approved_at, created_at)
            VALUES (\(bind: item.id), \(bind: item.userId), \(bind: item.status)::password_reset_status, \(bind: item.approvedBy), \(bind: item.note), \(bind: item.approvedAt), \(bind: item.createdAt))
            """).run()
        passwordResetRequestsInserted += 1
    }

    for item in payload.passwordResetTokens {
        let existsById = try await sqlRecordExists(sql: sql, table: "password_reset_tokens", id: item.id)
        let existsByHash = try await sqlTokenHashExists(sql: sql, table: "password_reset_tokens", tokenHash: item.tokenHash)
        if existsById || existsByHash {
            passwordResetTokensSkipped += 1
            continue
        }
        let requestExists = try await sqlRecordExists(sql: sql, table: "password_reset_requests", id: item.requestId)
        if !requestExists {
            passwordResetTokensSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO password_reset_tokens (id, request_id, token_hash, expires_at, used_at, created_at)
            VALUES (\(bind: item.id), \(bind: item.requestId), \(bind: item.tokenHash), \(bind: item.expiresAt), \(bind: item.usedAt), \(bind: item.createdAt))
            """).run()
        passwordResetTokensInserted += 1
    }

    for item in payload.apiTokens {
        let existsById = try await sqlRecordExists(sql: sql, table: "api_tokens", id: item.id)
        let existsByHash = try await sqlTokenHashExists(sql: sql, table: "api_tokens", tokenHash: item.tokenHash)
        if existsById || existsByHash {
            apiTokensSkipped += 1
            continue
        }
        let userExists = try await sqlRecordExists(sql: sql, table: "users", id: item.userId)
        if !userExists {
            apiTokensSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO api_tokens (id, user_id, token_hash, expires_at, created_at)
            VALUES (\(bind: item.id), \(bind: item.userId), \(bind: item.tokenHash), \(bind: item.expiresAt), \(bind: item.createdAt))
            """).run()
        apiTokensInserted += 1
    }

    for item in payload.auditEvents {
        if try await sqlRecordExists(sql: sql, table: "audit_events", id: item.id) {
            auditEventsSkipped += 1
            continue
        }
        var actorUserID: UUID? = item.actorUserId
        if let candidate = actorUserID {
            let actorExists = try await sqlRecordExists(sql: sql, table: "users", id: candidate)
            if !actorExists {
                actorUserID = nil
            }
        }
        try await sql.raw("""
            INSERT INTO audit_events (id, actor_user_id, actor_username, action, entity_type, entity_id, details, created_at)
            VALUES (\(bind: item.id), \(bind: actorUserID), \(bind: item.actorUsername), \(bind: item.action), \(bind: item.entityType), \(bind: item.entityId), \(bind: item.details), \(bind: item.createdAt))
            """).run()
        auditEventsInserted += 1
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "admin.data.import",
        entityType: "system",
        details: "version=\(payload.version)"
    )

    return .init(
        usersInserted: usersInserted,
        usersSkipped: usersSkipped,
        questsInserted: questsInserted,
        questsSkipped: questsSkipped,
        requirementsInserted: requirementsInserted,
        requirementsSkipped: requirementsSkipped,
        contributionsInserted: contributionsInserted,
        contributionsSkipped: contributionsSkipped,
        passwordResetRequestsInserted: passwordResetRequestsInserted,
        passwordResetRequestsSkipped: passwordResetRequestsSkipped,
        passwordResetTokensInserted: passwordResetTokensInserted,
        passwordResetTokensSkipped: passwordResetTokensSkipped,
        apiTokensInserted: apiTokensInserted,
        apiTokensSkipped: apiTokensSkipped,
        auditEventsInserted: auditEventsInserted,
        auditEventsSkipped: auditEventsSkipped
    )
}
