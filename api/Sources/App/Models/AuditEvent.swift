import Vapor
import Fluent

final class AuditEvent: Model, Content, @unchecked Sendable {
    static let schema = "audit_events"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "actor_user_id")
    var actorUser: User?

    @Field(key: "actor_username")
    var actorUsername: String

    @Field(key: "action")
    var action: String

    @Field(key: "entity_type")
    var entityType: String

    @OptionalField(key: "entity_id")
    var entityId: UUID?

    @OptionalField(key: "details")
    var details: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        actorUserID: UUID?,
        actorUsername: String,
        action: String,
        entityType: String,
        entityId: UUID? = nil,
        details: String? = nil
    ) {
        self.id = id
        self.$actorUser.id = actorUserID
        self.actorUsername = actorUsername
        self.action = action
        self.entityType = entityType
        self.entityId = entityId
        self.details = details
    }
}

struct CreateAuditEvent: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AuditEvent.schema)
            .id()
            .field("actor_user_id", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("actor_username", .string, .required)
            .field("action", .string, .required)
            .field("entity_type", .string, .required)
            .field("entity_id", .uuid)
            .field("details", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AuditEvent.schema).delete()
    }
}
