import Vapor

struct AuditEventResponseDTO: Content {
    let id: UUID
    let actorUsername: String
    let action: String
    let entityType: String
    let entityId: UUID?
    let details: String?
    let createdAt: Date?
}
