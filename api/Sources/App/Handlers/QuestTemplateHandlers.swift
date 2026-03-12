import Vapor
import Fluent
import SQLKit

private func sanitizeTemplateTitle(_ raw: String) throws -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        throw Abort(.badRequest, reason: "title is required")
    }
    guard value.count <= 120 else {
        throw Abort(.badRequest, reason: "title too long")
    }
    return value
}

private func sanitizeTemplateDescription(_ raw: String) throws -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        throw Abort(.badRequest, reason: "description is required")
    }
    return value
}

private func normalizeTemplateHandoverInfo(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
}

private func templateRequirementDTO(_ requirement: QuestTemplateRequirement) throws -> QuestTemplateRequirementResponseDTO {
    guard let id = requirement.id else { throw Abort(.internalServerError) }
    return .init(
        id: id,
        templateId: requirement.$template.id,
        itemName: requirement.itemName,
        qtyNeeded: requirement.qtyNeeded,
        unit: requirement.unit
    )
}

private func templateSummaryDTO(_ template: QuestTemplate, requirementCount: Int) throws -> QuestTemplateSummaryDTO {
    guard let id = template.id else { throw Abort(.internalServerError) }
    return .init(
        id: id,
        title: template.title,
        description: template.description,
        handoverInfo: template.handoverInfo,
        sourceQuestId: template.$sourceQuest.id,
        requirementCount: requirementCount,
        createdAt: template.createdAt
    )
}

private func loadTemplateDetail(_ templateId: UUID, on db: Database) async throws -> QuestTemplateDetailDTO {
    guard let template = try await QuestTemplate.find(templateId, on: db) else {
        throw Abort(.notFound)
    }

    let requirements = try await QuestTemplateRequirement.query(on: db)
        .filter(\.$template.$id == templateId)
        .sort(\.$itemName, .ascending)
        .all()

    return try .init(
        id: templateId,
        title: template.title,
        description: template.description,
        handoverInfo: template.handoverInfo,
        sourceQuestId: template.$sourceQuest.id,
        createdAt: template.createdAt,
        requirements: requirements.map(templateRequirementDTO)
    )
}

private func loadQuestResponseById(_ questId: UUID, on db: Database) async throws -> QuestResponseDTO {
    guard let sql = db as? SQLDatabase else {
        throw Abort(.internalServerError, reason: "SQL database unavailable")
    }

    let rows = try await sql.raw("""
        SELECT q.id, q.title, q.description, q.handover_info, q.status, q.created_at, q.created_by_user_id, q.is_approved, q.approved_at, u.username AS created_by_username
        FROM quests q
        LEFT JOIN users u ON u.id = q.created_by_user_id
        WHERE q.id = \(bind: questId)
        LIMIT 1
        """).all()

    guard let row = rows.first else {
        throw Abort(.notFound)
    }

    return try questFromRow(row)
}

func listQuestTemplates(_ req: Request) async throws -> [QuestTemplateSummaryDTO] {
    _ = try requireAdminOrSuperAdmin(req)

    let templates = try await QuestTemplate.query(on: req.db)
        .sort(\.$title, .ascending)
        .all()

    let counts = try await QuestTemplateRequirement.query(on: req.db).all().reduce(into: [UUID: Int]()) { partial, item in
        partial[item.$template.id, default: 0] += 1
    }

    return try templates.map { template in
        try templateSummaryDTO(template, requirementCount: template.id.flatMap { counts[$0] } ?? 0)
    }
}

func getQuestTemplate(_ req: Request) async throws -> QuestTemplateDetailDTO {
    _ = try requireAdminOrSuperAdmin(req)
    guard let templateId = req.parameters.get("templateID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    return try await loadTemplateDetail(templateId, on: req.db)
}

func createQuestTemplate(_ req: Request) async throws -> QuestTemplateDetailDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    let body = try req.content.decode(QuestTemplateCreateDTO.self)

    let template = QuestTemplate(
        title: try sanitizeTemplateTitle(body.title),
        description: try sanitizeTemplateDescription(body.description),
        handoverInfo: normalizeTemplateHandoverInfo(body.handoverInfo)
    )
    try await template.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "quest-template.create", entityType: "quest-template", entityId: template.id)
    return try await loadTemplateDetail(try template.requireID(), on: req.db)
}

func updateQuestTemplate(_ req: Request) async throws -> QuestTemplateDetailDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let templateId = req.parameters.get("templateID", as: UUID.self), let template = try await QuestTemplate.find(templateId, on: req.db) else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(QuestTemplateUpdateDTO.self)
    template.title = try sanitizeTemplateTitle(body.title)
    template.description = try sanitizeTemplateDescription(body.description)
    template.handoverInfo = normalizeTemplateHandoverInfo(body.handoverInfo)
    try await template.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "quest-template.update", entityType: "quest-template", entityId: template.id)
    return try await loadTemplateDetail(templateId, on: req.db)
}

func deleteQuestTemplate(_ req: Request) async throws -> HTTPStatus {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let templateId = req.parameters.get("templateID", as: UUID.self),
          let template = try await QuestTemplate.find(templateId, on: req.db) else {
        throw Abort(.notFound)
    }

    try await template.delete(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "quest-template.delete",
        entityType: "quest-template",
        entityId: templateId,
        details: "title=\(template.title)"
    )
    return .noContent
}

func createQuestTemplateRequirement(_ req: Request) async throws -> QuestTemplateDetailDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let templateId = req.parameters.get("templateID", as: UUID.self), try await QuestTemplate.find(templateId, on: req.db) != nil else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(QuestTemplateRequirementCreateDTO.self)
    let itemName = body.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !itemName.isEmpty else {
        throw Abort(.badRequest, reason: "itemName is required")
    }
    guard body.qtyNeeded > 0 else {
        throw Abort(.badRequest, reason: "qtyNeeded must be > 0")
    }

    let requirement = QuestTemplateRequirement(templateId: templateId, itemName: itemName, qtyNeeded: body.qtyNeeded, unit: body.unit)
    try await requirement.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "quest-template.requirement.create", entityType: "quest-template", entityId: templateId, details: "item=\(itemName)")
    return try await loadTemplateDetail(templateId, on: req.db)
}

func createQuestFromTemplate(_ req: Request) async throws -> QuestResponseDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let actorId = actor.id else {
        throw Abort(.internalServerError, reason: "user id missing")
    }
    guard let templateId = req.parameters.get("templateID", as: UUID.self), let template = try await QuestTemplate.find(templateId, on: req.db) else {
        throw Abort(.notFound)
    }

    let requirements = try await QuestTemplateRequirement.query(on: req.db)
        .filter(\.$template.$id == templateId)
        .all()

    let quest = Quest(
        title: template.title,
        description: template.description,
        handoverInfo: template.handoverInfo,
        status: Quest.Status.open.rawValue
    )
    try await quest.save(on: req.db)

    guard let questId = quest.id else { throw Abort(.internalServerError) }

    if let sql = req.db as? SQLDatabase {
        let now = Date()
        try await sql.raw("""
            UPDATE quests
            SET created_by_user_id = \(bind: actorId),
                is_approved = TRUE,
                approved_at = \(bind: now),
                approved_by_user_id = \(bind: actorId)
            WHERE id = \(bind: questId)
            """).run()
    }

    for item in requirements {
        let requirement = Requirement(questID: questId, itemName: item.itemName, qtyNeeded: item.qtyNeeded, unit: item.unit)
        try await requirement.save(on: req.db)
    }

    await recordAuditEvent(on: req, actor: actor, action: "quest-template.instantiate", entityType: "quest", entityId: questId, details: "templateId=\(templateId.uuidString)")
    return try await loadQuestResponseById(questId, on: req.db)
}

func createTemplateFromQuest(_ req: Request) async throws -> QuestTemplateDetailDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    guard let questId = req.parameters.get("questID", as: UUID.self), let quest = try await Quest.find(questId, on: req.db) else {
        throw Abort(.notFound)
    }

    let requirements = try await Requirement.query(on: req.db)
        .filter(\.$quest.$id == questId)
        .sort(\.$itemName, .ascending)
        .all()

    let template = QuestTemplate(
        title: quest.title,
        description: quest.description,
        handoverInfo: quest.handoverInfo,
        sourceQuestId: questId
    )
    try await template.save(on: req.db)
    let templateId = try template.requireID()

    for item in requirements {
        let requirement = QuestTemplateRequirement(templateId: templateId, itemName: item.itemName, qtyNeeded: item.qtyNeeded, unit: item.unit)
        try await requirement.save(on: req.db)
    }

    await recordAuditEvent(on: req, actor: actor, action: "quest-template.create-from-quest", entityType: "quest-template", entityId: templateId, details: "sourceQuestId=\(questId.uuidString)")
    return try await loadTemplateDetail(templateId, on: req.db)
}
