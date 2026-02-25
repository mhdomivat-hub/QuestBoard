import Vapor

func recordAuditEvent(
    on req: Request,
    actor: User,
    action: String,
    entityType: String,
    entityId: UUID? = nil,
    details: String? = nil
) async {
    let event = AuditEvent(
        actorUserID: actor.id,
        actorUsername: actor.username,
        action: action,
        entityType: entityType,
        entityId: entityId,
        details: details
    )

    do {
        try await event.save(on: req.db)
    } catch {
        req.logger.error("Audit event save failed: \(error)")
    }
}
