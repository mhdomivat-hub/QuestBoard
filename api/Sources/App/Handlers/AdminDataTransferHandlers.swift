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
        SELECT id, title, description, handover_info, status, terminal_since_at, deleted_at, created_at, created_by_user_id, is_approved, approved_at, approved_by_user_id, is_prioritized
        FROM quests
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let requirementRows = try await sql.raw("SELECT id, quest_id, item_name, qty_needed, unit FROM requirements ORDER BY item_name ASC, id ASC").all()
    let contributionRows = try await sql.raw("""
        SELECT id, requirement_id, user_id, qty, status, note, created_at
        FROM contributions
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let blueprintRows = try await sql.raw("""
        SELECT id, parent_id, name, description, item_code, badges_csv, category, is_craftable, created_at, updated_at
        FROM blueprints
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let blueprintCrafterRows = try await sql.raw("""
        SELECT id, blueprint_id, user_id, created_at
        FROM blueprint_crafters
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let storageLocationRows = try await sql.raw("""
        SELECT id, parent_id, name, description, created_at, updated_at
        FROM storage_locations
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let storageEntryRows = try await sql.raw("""
        SELECT id, item_id, location_id, user_id, qty, note, created_at
        FROM storage_entries
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let inviteRows = try await sql.raw("""
        SELECT id, token_hash, raw_token, role, max_uses, use_count, created_by_user_id, used_by_user_id, expires_at, used_at, revoked_at, created_at
        FROM invites
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let usernameChangeRequestRows = try await sql.raw("""
        SELECT id, user_id, current_username, desired_username, status, reviewed_by, reviewed_at, created_at
        FROM username_change_requests
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let questTemplateRows = try await sql.raw("""
        SELECT id, title, description, handover_info, source_quest_id, created_at
        FROM quest_templates
        ORDER BY created_at ASC NULLS LAST, id ASC
        """).all()
    let questTemplateRequirementRows = try await sql.raw("""
        SELECT id, template_id, item_name, qty_needed, unit
        FROM quest_template_requirements
        ORDER BY item_name ASC, id ASC
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

    let exportedUsers = try userRows.map {
        AdminExportUserDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            username: try $0.decode(column: "username", as: String.self),
            passwordHash: try $0.decode(column: "password_hash", as: String.self),
            role: try $0.decode(column: "role", as: String.self)
        )
    }
    let exportedQuests = try questRows.map {
        AdminExportQuestDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            title: try $0.decode(column: "title", as: String.self),
            description: try $0.decode(column: "description", as: String.self),
            handoverInfo: try decodeOptionalString($0, column: "handover_info"),
            status: try $0.decode(column: "status", as: String.self),
            terminalSinceAt: try decodeOptionalDate($0, column: "terminal_since_at"),
            deletedAt: try decodeOptionalDate($0, column: "deleted_at"),
            createdAt: try decodeOptionalDate($0, column: "created_at"),
            createdByUserId: try decodeOptionalUUID($0, column: "created_by_user_id"),
            isApproved: try $0.decode(column: "is_approved", as: Bool.self),
            approvedAt: try decodeOptionalDate($0, column: "approved_at"),
            approvedByUserId: try decodeOptionalUUID($0, column: "approved_by_user_id"),
            isPrioritized: try $0.decode(column: "is_prioritized", as: Bool.self)
        )
    }
    let exportedRequirements = try requirementRows.map {
        AdminExportRequirementDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            questId: try $0.decode(column: "quest_id", as: UUID.self),
            itemName: try $0.decode(column: "item_name", as: String.self),
            qtyNeeded: try $0.decode(column: "qty_needed", as: Int.self),
            unit: try $0.decode(column: "unit", as: String.self)
        )
    }
    let exportedContributions = try contributionRows.map {
        AdminExportContributionDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            requirementId: try $0.decode(column: "requirement_id", as: UUID.self),
            userId: try $0.decode(column: "user_id", as: UUID.self),
            qty: try $0.decode(column: "qty", as: Int.self),
            status: try $0.decode(column: "status", as: String.self),
            note: try decodeOptionalString($0, column: "note"),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedBlueprints = try blueprintRows.map {
        AdminExportBlueprintDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            parentId: try decodeOptionalUUID($0, column: "parent_id"),
            name: try $0.decode(column: "name", as: String.self),
            description: try decodeOptionalString($0, column: "description"),
            itemCode: try decodeOptionalString($0, column: "item_code"),
            badgesCSV: try decodeOptionalString($0, column: "badges_csv"),
            category: try $0.decode(column: "category", as: String.self),
            isCraftable: try $0.decode(column: "is_craftable", as: Bool.self),
            createdAt: try decodeOptionalDate($0, column: "created_at"),
            updatedAt: try decodeOptionalDate($0, column: "updated_at")
        )
    }
    let exportedBlueprintCrafters = try blueprintCrafterRows.map {
        AdminExportBlueprintCrafterDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            blueprintId: try $0.decode(column: "blueprint_id", as: UUID.self),
            userId: try $0.decode(column: "user_id", as: UUID.self),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedStorageLocations = try storageLocationRows.map {
        AdminExportStorageLocationDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            parentId: try decodeOptionalUUID($0, column: "parent_id"),
            name: try $0.decode(column: "name", as: String.self),
            description: try decodeOptionalString($0, column: "description"),
            createdAt: try decodeOptionalDate($0, column: "created_at"),
            updatedAt: try decodeOptionalDate($0, column: "updated_at")
        )
    }
    let exportedStorageEntries = try storageEntryRows.map {
        AdminExportStorageEntryDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            itemId: try $0.decode(column: "item_id", as: UUID.self),
            locationId: try $0.decode(column: "location_id", as: UUID.self),
            userId: try $0.decode(column: "user_id", as: UUID.self),
            qty: try $0.decode(column: "qty", as: Int.self),
            note: try decodeOptionalString($0, column: "note"),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedInvites = try inviteRows.map {
        AdminExportInviteDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            tokenHash: try $0.decode(column: "token_hash", as: String.self),
            rawToken: try decodeOptionalString($0, column: "raw_token"),
            role: try $0.decode(column: "role", as: String.self),
            maxUses: try $0.decode(column: "max_uses", as: Int.self),
            useCount: try $0.decode(column: "use_count", as: Int.self),
            createdByUserId: try $0.decode(column: "created_by_user_id", as: UUID.self),
            usedByUserId: try decodeOptionalUUID($0, column: "used_by_user_id"),
            expiresAt: try $0.decode(column: "expires_at", as: Date.self),
            usedAt: try decodeOptionalDate($0, column: "used_at"),
            revokedAt: try decodeOptionalDate($0, column: "revoked_at"),
            createdAt: try $0.decode(column: "created_at", as: Date.self)
        )
    }
    let exportedUsernameChangeRequests = try usernameChangeRequestRows.map {
        AdminExportUsernameChangeRequestDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            userId: try $0.decode(column: "user_id", as: UUID.self),
            currentUsername: try $0.decode(column: "current_username", as: String.self),
            desiredUsername: try $0.decode(column: "desired_username", as: String.self),
            status: try $0.decode(column: "status", as: String.self),
            reviewedBy: try decodeOptionalUUID($0, column: "reviewed_by"),
            reviewedAt: try decodeOptionalDate($0, column: "reviewed_at"),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedQuestTemplates = try questTemplateRows.map {
        AdminExportQuestTemplateDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            title: try $0.decode(column: "title", as: String.self),
            description: try $0.decode(column: "description", as: String.self),
            handoverInfo: try decodeOptionalString($0, column: "handover_info"),
            sourceQuestId: try decodeOptionalUUID($0, column: "source_quest_id"),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedQuestTemplateRequirements = try questTemplateRequirementRows.map {
        AdminExportQuestTemplateRequirementDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            templateId: try $0.decode(column: "template_id", as: UUID.self),
            itemName: try $0.decode(column: "item_name", as: String.self),
            qtyNeeded: try $0.decode(column: "qty_needed", as: Int.self),
            unit: try $0.decode(column: "unit", as: String.self)
        )
    }
    let exportedPasswordResetRequests = try requestRows.map {
        AdminExportPasswordResetRequestDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            userId: try $0.decode(column: "user_id", as: UUID.self),
            status: try $0.decode(column: "status", as: String.self),
            approvedBy: try decodeOptionalUUID($0, column: "approved_by"),
            note: try decodeOptionalString($0, column: "note"),
            approvedAt: try decodeOptionalDate($0, column: "approved_at"),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedPasswordResetTokens = try resetTokenRows.map {
        AdminExportPasswordResetTokenDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            requestId: try $0.decode(column: "request_id", as: UUID.self),
            tokenHash: try $0.decode(column: "token_hash", as: String.self),
            expiresAt: try $0.decode(column: "expires_at", as: Date.self),
            usedAt: try decodeOptionalDate($0, column: "used_at"),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedAPITokens = try apiTokenRows.map {
        AdminExportAPITokenDTO(
            id: try $0.decode(column: "id", as: UUID.self),
            userId: try $0.decode(column: "user_id", as: UUID.self),
            tokenHash: try $0.decode(column: "token_hash", as: String.self),
            expiresAt: try $0.decode(column: "expires_at", as: Date.self),
            createdAt: try decodeOptionalDate($0, column: "created_at")
        )
    }
    let exportedAuditEvents = try auditRows.map {
        AdminExportAuditEventDTO(
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

    return AdminDataExportDTO(
        version: 1,
        generatedAt: Date(),
        users: exportedUsers,
        quests: exportedQuests,
        requirements: exportedRequirements,
        contributions: exportedContributions,
        blueprints: exportedBlueprints,
        blueprintCrafters: exportedBlueprintCrafters,
        storageLocations: exportedStorageLocations,
        storageEntries: exportedStorageEntries,
        invites: exportedInvites,
        usernameChangeRequests: exportedUsernameChangeRequests,
        questTemplates: exportedQuestTemplates,
        questTemplateRequirements: exportedQuestTemplateRequirements,
        passwordResetRequests: exportedPasswordResetRequests,
        passwordResetTokens: exportedPasswordResetTokens,
        apiTokens: exportedAPITokens,
        auditEvents: exportedAuditEvents
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

private func encodeTransferPayload<T: Encodable>(_ value: T) throws -> ByteBuffer {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return ByteBuffer(data: data)
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
            blueprints: try await countAllRows(sql: sql, table: "blueprints"),
            blueprintCrafters: try await countAllRows(sql: sql, table: "blueprint_crafters"),
            storageLocations: try await countAllRows(sql: sql, table: "storage_locations"),
            storageEntries: try await countAllRows(sql: sql, table: "storage_entries"),
            invites: try await countAllRows(sql: sql, table: "invites"),
            usernameChangeRequests: try await countAllRows(sql: sql, table: "username_change_requests"),
            questTemplates: try await countAllRows(sql: sql, table: "quest_templates"),
            questTemplateRequirements: try await countAllRows(sql: sql, table: "quest_template_requirements"),
            passwordResetRequests: try await countAllRows(sql: sql, table: "password_reset_requests"),
            passwordResetTokens: try await countAllRows(sql: sql, table: "password_reset_tokens"),
            apiTokens: try await countAllRows(sql: sql, table: "api_tokens"),
            auditEvents: try await countAllRows(sql: sql, table: "audit_events")
        )
    )
}

private func exportDataSectionPayload(
    sql: SQLDatabase,
    section: String,
    limit: Int,
    offset: Int,
    generatedAt: Date = Date()
) async throws -> AdminDataExportDTO {
    let section = section.lowercased()
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
            SELECT id, title, description, handover_info, status, terminal_since_at, deleted_at, created_at, created_by_user_id, is_approved, approved_at, approved_by_user_id, is_prioritized
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
                    handoverInfo: try decodeOptionalString($0, column: "handover_info"),
                    status: try $0.decode(column: "status", as: String.self),
                    terminalSinceAt: try decodeOptionalDate($0, column: "terminal_since_at"),
                    deletedAt: try decodeOptionalDate($0, column: "deleted_at"),
                    createdAt: try decodeOptionalDate($0, column: "created_at"),
                    createdByUserId: try decodeOptionalUUID($0, column: "created_by_user_id"),
                    isApproved: try $0.decode(column: "is_approved", as: Bool.self),
                    approvedAt: try decodeOptionalDate($0, column: "approved_at"),
                    approvedByUserId: try decodeOptionalUUID($0, column: "approved_by_user_id"),
                    isPrioritized: try $0.decode(column: "is_prioritized", as: Bool.self)
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
    case "blueprints":
        let rows = try await sql.raw("""
            SELECT id, parent_id, name, description, item_code, badges_csv, category, is_craftable, created_at, updated_at
            FROM blueprints
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
            blueprints: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    parentId: try decodeOptionalUUID($0, column: "parent_id"),
                    name: try $0.decode(column: "name", as: String.self),
                    description: try decodeOptionalString($0, column: "description"),
                    itemCode: try decodeOptionalString($0, column: "item_code"),
                    badgesCSV: try decodeOptionalString($0, column: "badges_csv"),
                    category: try $0.decode(column: "category", as: String.self),
                    isCraftable: try $0.decode(column: "is_craftable", as: Bool.self),
                    createdAt: try decodeOptionalDate($0, column: "created_at"),
                    updatedAt: try decodeOptionalDate($0, column: "updated_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "blueprintcrafters":
        let rows = try await sql.raw("""
            SELECT id, blueprint_id, user_id, created_at
            FROM blueprint_crafters
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
            blueprintCrafters: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    blueprintId: try $0.decode(column: "blueprint_id", as: UUID.self),
                    userId: try $0.decode(column: "user_id", as: UUID.self),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "storagelocations":
        let rows = try await sql.raw("""
            SELECT id, parent_id, name, description, created_at, updated_at
            FROM storage_locations
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
            storageLocations: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    parentId: try decodeOptionalUUID($0, column: "parent_id"),
                    name: try $0.decode(column: "name", as: String.self),
                    description: try decodeOptionalString($0, column: "description"),
                    createdAt: try decodeOptionalDate($0, column: "created_at"),
                    updatedAt: try decodeOptionalDate($0, column: "updated_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "storageentries":
        let rows = try await sql.raw("""
            SELECT id, item_id, location_id, user_id, qty, note, created_at
            FROM storage_entries
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
            storageEntries: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    itemId: try $0.decode(column: "item_id", as: UUID.self),
                    locationId: try $0.decode(column: "location_id", as: UUID.self),
                    userId: try $0.decode(column: "user_id", as: UUID.self),
                    qty: try $0.decode(column: "qty", as: Int.self),
                    note: try decodeOptionalString($0, column: "note"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "invites":
        let rows = try await sql.raw("""
            SELECT id, token_hash, raw_token, role, max_uses, use_count, created_by_user_id, used_by_user_id, expires_at, used_at, revoked_at, created_at
            FROM invites
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
            invites: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    tokenHash: try $0.decode(column: "token_hash", as: String.self),
                    rawToken: try decodeOptionalString($0, column: "raw_token"),
                    role: try $0.decode(column: "role", as: String.self),
                    maxUses: try $0.decode(column: "max_uses", as: Int.self),
                    useCount: try $0.decode(column: "use_count", as: Int.self),
                    createdByUserId: try $0.decode(column: "created_by_user_id", as: UUID.self),
                    usedByUserId: try decodeOptionalUUID($0, column: "used_by_user_id"),
                    expiresAt: try $0.decode(column: "expires_at", as: Date.self),
                    usedAt: try decodeOptionalDate($0, column: "used_at"),
                    revokedAt: try decodeOptionalDate($0, column: "revoked_at"),
                    createdAt: try $0.decode(column: "created_at", as: Date.self)
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "usernamechangerequests":
        let rows = try await sql.raw("""
            SELECT id, user_id, current_username, desired_username, status, reviewed_by, reviewed_at, created_at
            FROM username_change_requests
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
            usernameChangeRequests: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    userId: try $0.decode(column: "user_id", as: UUID.self),
                    currentUsername: try $0.decode(column: "current_username", as: String.self),
                    desiredUsername: try $0.decode(column: "desired_username", as: String.self),
                    status: try $0.decode(column: "status", as: String.self),
                    reviewedBy: try decodeOptionalUUID($0, column: "reviewed_by"),
                    reviewedAt: try decodeOptionalDate($0, column: "reviewed_at"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "questtemplates":
        let rows = try await sql.raw("""
            SELECT id, title, description, handover_info, source_quest_id, created_at
            FROM quest_templates
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
            questTemplates: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    title: try $0.decode(column: "title", as: String.self),
                    description: try $0.decode(column: "description", as: String.self),
                    handoverInfo: try decodeOptionalString($0, column: "handover_info"),
                    sourceQuestId: try decodeOptionalUUID($0, column: "source_quest_id"),
                    createdAt: try decodeOptionalDate($0, column: "created_at")
                )
            },
            passwordResetRequests: [],
            passwordResetTokens: [],
            apiTokens: [],
            auditEvents: []
        )
    case "questtemplaterequirements":
        let rows = try await sql.raw("""
            SELECT id, template_id, item_name, qty_needed, unit
            FROM quest_template_requirements
            ORDER BY item_name ASC, id ASC
            LIMIT \(bind: limit) OFFSET \(bind: offset)
            """).all()
        result = .init(
            version: 1,
            generatedAt: generatedAt,
            users: [],
            quests: [],
            requirements: [],
            contributions: [],
            questTemplateRequirements: try rows.map {
                .init(
                    id: try $0.decode(column: "id", as: UUID.self),
                    templateId: try $0.decode(column: "template_id", as: UUID.self),
                    itemName: try $0.decode(column: "item_name", as: String.self),
                    qtyNeeded: try $0.decode(column: "qty_needed", as: Int.self),
                    unit: try $0.decode(column: "unit", as: String.self)
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

func exportDataSection(_ req: Request) async throws -> AdminDataExportDTO {
    let _ = try requireSuperAdmin(req)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let section = try req.parameters.require("section")
    let limit = parseLimit(req)
    let offset = parseOffset(req)
    return try await exportDataSectionPayload(sql: sql, section: section, limit: limit, offset: offset)
}

private func importAllDataPayload(
    req: Request,
    actor: User,
    sql: SQLDatabase,
    payload: AdminDataExportDTO,
    recordAudit: Bool = true
) async throws -> AdminDataImportResultDTO {
    var usersInserted = 0
    var usersSkipped = 0
    var questsInserted = 0
    var questsSkipped = 0
    var requirementsInserted = 0
    var requirementsSkipped = 0
    var contributionsInserted = 0
    var contributionsSkipped = 0
    var blueprintsInserted = 0
    var blueprintsSkipped = 0
    var blueprintCraftersInserted = 0
    var blueprintCraftersSkipped = 0
    var storageLocationsInserted = 0
    var storageLocationsSkipped = 0
    var storageEntriesInserted = 0
    var storageEntriesSkipped = 0
    var invitesInserted = 0
    var invitesSkipped = 0
    var usernameChangeRequestsInserted = 0
    var usernameChangeRequestsSkipped = 0
    var questTemplatesInserted = 0
    var questTemplatesSkipped = 0
    var questTemplateRequirementsInserted = 0
    var questTemplateRequirementsSkipped = 0
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
            INSERT INTO quests (id, title, description, handover_info, status, terminal_since_at, deleted_at, created_at, created_by_user_id, is_approved, approved_at, approved_by_user_id)
            VALUES (
                \(bind: item.id), \(bind: item.title), \(bind: item.description), \(bind: item.handoverInfo), \(bind: item.status),
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

    for item in payload.blueprints {
        if try await sqlRecordExists(sql: sql, table: "blueprints", id: item.id) {
            blueprintsSkipped += 1
            continue
        }
        if let parentId = item.parentId, !(try await sqlRecordExists(sql: sql, table: "blueprints", id: parentId)) {
            blueprintsSkipped += 1
            continue
        }
        guard BlueprintCategory(rawValue: item.category) != nil else {
            blueprintsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO blueprints (id, parent_id, name, description, item_code, badges_csv, category, is_craftable, created_at, updated_at)
            VALUES (
                \(bind: item.id), \(bind: item.parentId), \(bind: item.name), \(bind: item.description), \(bind: item.itemCode),
                \(bind: item.badgesCSV), \(bind: item.category)::blueprint_category, \(bind: item.isCraftable), \(bind: item.createdAt), \(bind: item.updatedAt)
            """).run()
        blueprintsInserted += 1
    }

    for item in payload.blueprintCrafters {
        if try await sqlRecordExists(sql: sql, table: "blueprint_crafters", id: item.id) {
            blueprintCraftersSkipped += 1
            continue
        }
        let blueprintExists = try await sqlRecordExists(sql: sql, table: "blueprints", id: item.blueprintId)
        let userExists = try await sqlRecordExists(sql: sql, table: "users", id: item.userId)
        if !blueprintExists || !userExists {
            blueprintCraftersSkipped += 1
            continue
        }
        let duplicateRows = try await sql.raw("""
            SELECT 1 FROM blueprint_crafters
            WHERE blueprint_id = \(bind: item.blueprintId) AND user_id = \(bind: item.userId)
            LIMIT 1
            """).all()
        if !duplicateRows.isEmpty {
            blueprintCraftersSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO blueprint_crafters (id, blueprint_id, user_id, created_at)
            VALUES (\(bind: item.id), \(bind: item.blueprintId), \(bind: item.userId), \(bind: item.createdAt))
            """).run()
        blueprintCraftersInserted += 1
    }

    for item in payload.storageLocations {
        if try await sqlRecordExists(sql: sql, table: "storage_locations", id: item.id) {
            storageLocationsSkipped += 1
            continue
        }
        if let parentId = item.parentId, !(try await sqlRecordExists(sql: sql, table: "storage_locations", id: parentId)) {
            storageLocationsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO storage_locations (id, parent_id, name, description, created_at, updated_at)
            VALUES (\(bind: item.id), \(bind: item.parentId), \(bind: item.name), \(bind: item.description), \(bind: item.createdAt), \(bind: item.updatedAt))
            """).run()
        storageLocationsInserted += 1
    }

    for item in payload.storageEntries {
        if try await sqlRecordExists(sql: sql, table: "storage_entries", id: item.id) {
            storageEntriesSkipped += 1
            continue
        }
        let blueprintExists = try await sqlRecordExists(sql: sql, table: "blueprints", id: item.itemId)
        let locationExists = try await sqlRecordExists(sql: sql, table: "storage_locations", id: item.locationId)
        let userExists = try await sqlRecordExists(sql: sql, table: "users", id: item.userId)
        if !blueprintExists || !locationExists || !userExists {
            storageEntriesSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO storage_entries (id, item_id, location_id, user_id, qty, note, created_at)
            VALUES (\(bind: item.id), \(bind: item.itemId), \(bind: item.locationId), \(bind: item.userId), \(bind: item.qty), \(bind: item.note), \(bind: item.createdAt))
            """).run()
        storageEntriesInserted += 1
    }

    for item in payload.invites {
        let existsById = try await sqlRecordExists(sql: sql, table: "invites", id: item.id)
        let existsByHash = try await sqlTokenHashExists(sql: sql, table: "invites", tokenHash: item.tokenHash)
        if existsById || existsByHash {
            invitesSkipped += 1
            continue
        }
        let createdByExists = try await sqlRecordExists(sql: sql, table: "users", id: item.createdByUserId)
        if !createdByExists {
            invitesSkipped += 1
            continue
        }
        if let usedByUserId = item.usedByUserId, !(try await sqlRecordExists(sql: sql, table: "users", id: usedByUserId)) {
            invitesSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO invites (id, token_hash, raw_token, role, max_uses, use_count, created_by_user_id, used_by_user_id, expires_at, used_at, revoked_at, created_at)
            VALUES (
                \(bind: item.id), \(bind: item.tokenHash), \(bind: item.rawToken), \(bind: item.role), \(bind: item.maxUses), \(bind: item.useCount),
                \(bind: item.createdByUserId), \(bind: item.usedByUserId), \(bind: item.expiresAt), \(bind: item.usedAt), \(bind: item.revokedAt), \(bind: item.createdAt))
            """).run()
        invitesInserted += 1
    }

    for item in payload.usernameChangeRequests {
        if try await sqlRecordExists(sql: sql, table: "username_change_requests", id: item.id) {
            usernameChangeRequestsSkipped += 1
            continue
        }
        let userExists = try await sqlRecordExists(sql: sql, table: "users", id: item.userId)
        if !userExists {
            usernameChangeRequestsSkipped += 1
            continue
        }
        if let reviewedBy = item.reviewedBy, !(try await sqlRecordExists(sql: sql, table: "users", id: reviewedBy)) {
            usernameChangeRequestsSkipped += 1
            continue
        }
        guard UsernameChangeRequestStatus(rawValue: item.status) != nil else {
            usernameChangeRequestsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO username_change_requests (id, user_id, current_username, desired_username, status, reviewed_by, reviewed_at, created_at)
            VALUES (
                \(bind: item.id), \(bind: item.userId), \(bind: item.currentUsername), \(bind: item.desiredUsername),
                \(bind: item.status)::username_change_request_status, \(bind: item.reviewedBy), \(bind: item.reviewedAt), \(bind: item.createdAt))
            """).run()
        usernameChangeRequestsInserted += 1
    }

    for item in payload.questTemplates {
        if try await sqlRecordExists(sql: sql, table: "quest_templates", id: item.id) {
            questTemplatesSkipped += 1
            continue
        }
        if let sourceQuestId = item.sourceQuestId, !(try await sqlRecordExists(sql: sql, table: "quests", id: sourceQuestId)) {
            questTemplatesSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO quest_templates (id, title, description, handover_info, source_quest_id, created_at)
            VALUES (\(bind: item.id), \(bind: item.title), \(bind: item.description), \(bind: item.handoverInfo), \(bind: item.sourceQuestId), \(bind: item.createdAt))
            """).run()
        questTemplatesInserted += 1
    }

    for item in payload.questTemplateRequirements {
        if try await sqlRecordExists(sql: sql, table: "quest_template_requirements", id: item.id) {
            questTemplateRequirementsSkipped += 1
            continue
        }
        let templateExists = try await sqlRecordExists(sql: sql, table: "quest_templates", id: item.templateId)
        if !templateExists {
            questTemplateRequirementsSkipped += 1
            continue
        }
        try await sql.raw("""
            INSERT INTO quest_template_requirements (id, template_id, item_name, qty_needed, unit)
            VALUES (\(bind: item.id), \(bind: item.templateId), \(bind: item.itemName), \(bind: item.qtyNeeded), \(bind: item.unit))
            """).run()
        questTemplateRequirementsInserted += 1
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

    if recordAudit {
        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "admin.data.import",
            entityType: "system",
            details: "version=\(payload.version)"
        )
    }

    return .init(
        usersInserted: usersInserted,
        usersSkipped: usersSkipped,
        questsInserted: questsInserted,
        questsSkipped: questsSkipped,
        requirementsInserted: requirementsInserted,
        requirementsSkipped: requirementsSkipped,
        contributionsInserted: contributionsInserted,
        contributionsSkipped: contributionsSkipped,
        blueprintsInserted: blueprintsInserted,
        blueprintsSkipped: blueprintsSkipped,
        blueprintCraftersInserted: blueprintCraftersInserted,
        blueprintCraftersSkipped: blueprintCraftersSkipped,
        storageLocationsInserted: storageLocationsInserted,
        storageLocationsSkipped: storageLocationsSkipped,
        storageEntriesInserted: storageEntriesInserted,
        storageEntriesSkipped: storageEntriesSkipped,
        invitesInserted: invitesInserted,
        invitesSkipped: invitesSkipped,
        usernameChangeRequestsInserted: usernameChangeRequestsInserted,
        usernameChangeRequestsSkipped: usernameChangeRequestsSkipped,
        questTemplatesInserted: questTemplatesInserted,
        questTemplatesSkipped: questTemplatesSkipped,
        questTemplateRequirementsInserted: questTemplateRequirementsInserted,
        questTemplateRequirementsSkipped: questTemplateRequirementsSkipped,
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

func importAllData(_ req: Request) async throws -> AdminDataImportResultDTO {
    let actor = try requireSuperAdmin(req)
    let payload = try req.content.decode(AdminDataExportDTO.self)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    return try await importAllDataPayload(req: req, actor: actor, sql: sql, payload: payload)
}

private func normalizeRemoteBaseURL(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw Abort(.badRequest, reason: "Source URL is required")
    }

    guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased() else {
        throw Abort(.badRequest, reason: "Source URL is invalid")
    }

    guard scheme == "http" || scheme == "https" else {
        throw Abort(.badRequest, reason: "Source URL must use http or https")
    }

    guard components.host != nil else {
        throw Abort(.badRequest, reason: "Source URL must include a host")
    }

    return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
}

private func decodeRemoteJSON<T: Decodable>(
    _ type: T.Type,
    from response: ClientResponse,
    req: Request,
    context: String
) async throws -> T {
    guard response.status == .ok else {
        let bodyText = response.body.flatMap { $0.getString(at: 0, length: $0.readableBytes) } ?? ""
        throw Abort(.badGateway, reason: "\(context) failed with HTTP \(response.status.code). \(bodyText)")
    }

    let bodyData = response.body.map { Data(buffer: $0) } ?? Data()
    do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: bodyData)
    } catch {
        req.logger.error("Remote transfer decode failure for \(context): \(error)")
        throw Abort(.badGateway, reason: "\(context) returned invalid JSON")
    }
}

private func sumImportResults(_ current: AdminDataImportResultDTO, _ next: AdminDataImportResultDTO) -> AdminDataImportResultDTO {
    .init(
        usersInserted: current.usersInserted + next.usersInserted,
        usersSkipped: current.usersSkipped + next.usersSkipped,
        questsInserted: current.questsInserted + next.questsInserted,
        questsSkipped: current.questsSkipped + next.questsSkipped,
        requirementsInserted: current.requirementsInserted + next.requirementsInserted,
        requirementsSkipped: current.requirementsSkipped + next.requirementsSkipped,
        contributionsInserted: current.contributionsInserted + next.contributionsInserted,
        contributionsSkipped: current.contributionsSkipped + next.contributionsSkipped,
        blueprintsInserted: current.blueprintsInserted + next.blueprintsInserted,
        blueprintsSkipped: current.blueprintsSkipped + next.blueprintsSkipped,
        blueprintCraftersInserted: current.blueprintCraftersInserted + next.blueprintCraftersInserted,
        blueprintCraftersSkipped: current.blueprintCraftersSkipped + next.blueprintCraftersSkipped,
        storageLocationsInserted: current.storageLocationsInserted + next.storageLocationsInserted,
        storageLocationsSkipped: current.storageLocationsSkipped + next.storageLocationsSkipped,
        storageEntriesInserted: current.storageEntriesInserted + next.storageEntriesInserted,
        storageEntriesSkipped: current.storageEntriesSkipped + next.storageEntriesSkipped,
        invitesInserted: current.invitesInserted + next.invitesInserted,
        invitesSkipped: current.invitesSkipped + next.invitesSkipped,
        usernameChangeRequestsInserted: current.usernameChangeRequestsInserted + next.usernameChangeRequestsInserted,
        usernameChangeRequestsSkipped: current.usernameChangeRequestsSkipped + next.usernameChangeRequestsSkipped,
        questTemplatesInserted: current.questTemplatesInserted + next.questTemplatesInserted,
        questTemplatesSkipped: current.questTemplatesSkipped + next.questTemplatesSkipped,
        questTemplateRequirementsInserted: current.questTemplateRequirementsInserted + next.questTemplateRequirementsInserted,
        questTemplateRequirementsSkipped: current.questTemplateRequirementsSkipped + next.questTemplateRequirementsSkipped,
        passwordResetRequestsInserted: current.passwordResetRequestsInserted + next.passwordResetRequestsInserted,
        passwordResetRequestsSkipped: current.passwordResetRequestsSkipped + next.passwordResetRequestsSkipped,
        passwordResetTokensInserted: current.passwordResetTokensInserted + next.passwordResetTokensInserted,
        passwordResetTokensSkipped: current.passwordResetTokensSkipped + next.passwordResetTokensSkipped,
        apiTokensInserted: current.apiTokensInserted + next.apiTokensInserted,
        apiTokensSkipped: current.apiTokensSkipped + next.apiTokensSkipped,
        auditEventsInserted: current.auditEventsInserted + next.auditEventsInserted,
        auditEventsSkipped: current.auditEventsSkipped + next.auditEventsSkipped
    )
}

private func emptyImportResult() -> AdminDataImportResultDTO {
    .init(
        usersInserted: 0,
        usersSkipped: 0,
        questsInserted: 0,
        questsSkipped: 0,
        requirementsInserted: 0,
        requirementsSkipped: 0,
        contributionsInserted: 0,
        contributionsSkipped: 0,
        blueprintsInserted: 0,
        blueprintsSkipped: 0,
        blueprintCraftersInserted: 0,
        blueprintCraftersSkipped: 0,
        storageLocationsInserted: 0,
        storageLocationsSkipped: 0,
        storageEntriesInserted: 0,
        storageEntriesSkipped: 0,
        invitesInserted: 0,
        invitesSkipped: 0,
        usernameChangeRequestsInserted: 0,
        usernameChangeRequestsSkipped: 0,
        questTemplatesInserted: 0,
        questTemplatesSkipped: 0,
        questTemplateRequirementsInserted: 0,
        questTemplateRequirementsSkipped: 0,
        passwordResetRequestsInserted: 0,
        passwordResetRequestsSkipped: 0,
        passwordResetTokensInserted: 0,
        passwordResetTokensSkipped: 0,
        apiTokensInserted: 0,
        apiTokensSkipped: 0,
        auditEventsInserted: 0,
        auditEventsSkipped: 0
    )
}

private let remoteTransferSections: [(section: String, manifestCount: KeyPath<AdminDataExportManifestCountsDTO, Int>)] = [
    ("users", \.users),
    ("quests", \.quests),
    ("requirements", \.requirements),
    ("contributions", \.contributions),
    ("blueprints", \.blueprints),
    ("blueprintCrafters", \.blueprintCrafters),
    ("storageLocations", \.storageLocations),
    ("storageEntries", \.storageEntries),
    ("invites", \.invites),
    ("usernameChangeRequests", \.usernameChangeRequests),
    ("questTemplates", \.questTemplates),
    ("questTemplateRequirements", \.questTemplateRequirements),
    ("passwordResetRequests", \.passwordResetRequests),
    ("passwordResetTokens", \.passwordResetTokens),
    ("apiTokens", \.apiTokens),
    ("auditEvents", \.auditEvents)
]

private func resolveRequestedRemoteSections(_ requested: [String]?) throws -> [String] {
    let allowed = Set(remoteTransferSections.map(\.section))
    let normalized = (requested ?? remoteTransferSections.map(\.section)).map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }

    guard !normalized.isEmpty else {
        throw Abort(.badRequest, reason: "At least one transfer section must be selected")
    }

    for section in normalized where !allowed.contains(section) {
        throw Abort(.badRequest, reason: "Unknown transfer section: \(section)")
    }

    var seen = Set<String>()
    return normalized.filter { seen.insert($0).inserted }
}

func transferRemoteData(_ req: Request) async throws -> AdminRemoteTransferResultDTO {
    let actor = try requireSuperAdmin(req)
    let payload = try req.content.decode(AdminRemoteTransferRequestDTO.self)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let sourceBaseURL = try normalizeRemoteBaseURL(payload.sourceBaseURL)
    let sourceToken = payload.sourceToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedSections = try resolveRequestedRemoteSections(payload.sections)
    guard !sourceToken.isEmpty else {
        throw Abort(.badRequest, reason: "Source token is required")
    }

    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(sourceToken)")

    let manifestResponse = try await req.client.get(URI(string: "\(sourceBaseURL)/admin/data/export/manifest"), headers: headers)
    let manifest = try await decodeRemoteJSON(AdminDataExportManifestDTO.self, from: manifestResponse, req: req, context: "Remote manifest")

    let sections = remoteTransferSections
        .filter { selectedSections.contains($0.section) }
        .map { (section: $0.section, count: manifest.counts[keyPath: $0.manifestCount]) }

    let chunkSize = 500
    var chunksFetched = 0
    var aggregate = emptyImportResult()

    for entry in sections where entry.count > 0 {
        let chunkCount = Int(ceil(Double(entry.count) / Double(chunkSize)))
        for chunkIndex in 0..<chunkCount {
            let offset = chunkIndex * chunkSize
            let url = "\(sourceBaseURL)/admin/data/export/\(entry.section)?limit=\(chunkSize)&offset=\(offset)"
            let chunkResponse = try await req.client.get(URI(string: url), headers: headers)
            let chunkPayload = try await decodeRemoteJSON(AdminDataExportDTO.self, from: chunkResponse, req: req, context: "Remote \(entry.section) chunk \(chunkIndex + 1)")
            let chunkResult = try await importAllDataPayload(req: req, actor: actor, sql: sql, payload: chunkPayload, recordAudit: false)
            aggregate = sumImportResults(aggregate, chunkResult)
            chunksFetched += 1
        }
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "admin.data.transfer_remote",
        entityType: "system",
        details: "source=\(sourceBaseURL),chunks=\(chunksFetched),sections=\(selectedSections.joined(separator: ","))"
    )

    return .init(
        manifest: manifest,
        chunksFetched: chunksFetched,
        sections: selectedSections,
        importResult: aggregate
    )
}

func pushRemoteData(_ req: Request) async throws -> AdminRemotePushResultDTO {
    let actor = try requireSuperAdmin(req)
    let payload = try req.content.decode(AdminRemotePushRequestDTO.self)
    guard let sql = req.db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let targetBaseURL = try normalizeRemoteBaseURL(payload.targetBaseURL)
    let targetToken = payload.targetToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedSections = try resolveRequestedRemoteSections(payload.sections)
    guard !targetToken.isEmpty else {
        throw Abort(.badRequest, reason: "Target token is required")
    }

    let manifestCounts = try await AdminDataExportManifestCountsDTO(
        users: try await countAllRows(sql: sql, table: "users"),
        quests: try await countAllRows(sql: sql, table: "quests"),
        requirements: try await countAllRows(sql: sql, table: "requirements"),
        contributions: try await countAllRows(sql: sql, table: "contributions"),
        blueprints: try await countAllRows(sql: sql, table: "blueprints"),
        blueprintCrafters: try await countAllRows(sql: sql, table: "blueprint_crafters"),
        storageLocations: try await countAllRows(sql: sql, table: "storage_locations"),
        storageEntries: try await countAllRows(sql: sql, table: "storage_entries"),
        invites: try await countAllRows(sql: sql, table: "invites"),
        usernameChangeRequests: try await countAllRows(sql: sql, table: "username_change_requests"),
        questTemplates: try await countAllRows(sql: sql, table: "quest_templates"),
        questTemplateRequirements: try await countAllRows(sql: sql, table: "quest_template_requirements"),
        passwordResetRequests: try await countAllRows(sql: sql, table: "password_reset_requests"),
        passwordResetTokens: try await countAllRows(sql: sql, table: "password_reset_tokens"),
        apiTokens: try await countAllRows(sql: sql, table: "api_tokens"),
        auditEvents: try await countAllRows(sql: sql, table: "audit_events")
    )
    let manifest = AdminDataExportManifestDTO(
        version: 1,
        generatedAt: Date(),
        counts: manifestCounts
    )

    var headers = HTTPHeaders()
    headers.add(name: .authorization, value: "Bearer \(targetToken)")
    headers.add(name: .contentType, value: "application/json")

    let chunkSize = 500
    var chunksSent = 0
    var aggregate = emptyImportResult()

    for entry in remoteTransferSections where selectedSections.contains(entry.section) {
        let totalCount = manifest.counts[keyPath: entry.manifestCount]
        guard totalCount > 0 else { continue }

        let chunkCount = Int(ceil(Double(totalCount) / Double(chunkSize)))
        for chunkIndex in 0..<chunkCount {
            let offset = chunkIndex * chunkSize
            let chunkPayload = try await exportDataSectionPayload(
                sql: sql,
                section: entry.section,
                limit: chunkSize,
                offset: offset,
                generatedAt: manifest.generatedAt
            )
            let response = try await req.client.post(
                URI(string: "\(targetBaseURL)/admin/data/import"),
                headers: headers
            ) { clientRequest in
                clientRequest.body = try encodeTransferPayload(chunkPayload)
            }
            let chunkResult = try await decodeRemoteJSON(
                AdminDataImportResultDTO.self,
                from: response,
                req: req,
                context: "Remote target import for \(entry.section) chunk \(chunkIndex + 1)"
            )
            aggregate = sumImportResults(aggregate, chunkResult)
            chunksSent += 1
        }
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "admin.data.push_remote",
        entityType: "system",
        details: "target=\(targetBaseURL),chunks=\(chunksSent),sections=\(selectedSections.joined(separator: ","))"
    )

    return .init(
        manifest: manifest,
        chunksSent: chunksSent,
        sections: selectedSections,
        importResult: aggregate
    )
}

