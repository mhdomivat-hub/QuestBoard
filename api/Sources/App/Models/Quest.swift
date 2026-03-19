import Vapor
import Fluent
import SQLKit

final class Quest: Model, Content, @unchecked Sendable {
    static let schema = "quests"

    enum Status: String, Codable {
        case open = "OPEN"
        case inProgress = "IN_PROGRESS"
        case done = "DONE"
        case archived = "ARCHIVED"
    }

    static let allowedStatuses: Set<String> = [
        Status.open.rawValue,
        Status.inProgress.rawValue,
        Status.done.rawValue,
        Status.archived.rawValue
    ]

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @Field(key: "description")
    var description: String

    @OptionalField(key: "handover_info")
    var handoverInfo: String?

    @Field(key: "status")
    var status: String

    @Field(key: "is_prioritized")
    var isPrioritized: Bool

    @OptionalField(key: "terminal_since_at")
    var terminalSinceAt: Date?

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        title: String,
        description: String,
        handoverInfo: String? = nil,
        status: String = Status.open.rawValue,
        isPrioritized: Bool = false
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.handoverInfo = handoverInfo
        self.status = status
        self.isPrioritized = isPrioritized
    }
}

struct CreateQuest: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .id()
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("status", .string, .required)
            .field("is_prioritized", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Quest.schema).delete()
    }
}

struct AddQuestRetentionFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .field("terminal_since_at", .datetime)
            .field("deleted_at", .datetime)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .deleteField("deleted_at")
            .deleteField("terminal_since_at")
            .update()
    }
}

struct AddQuestApprovalFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .field("created_by_user_id", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("is_approved", .bool, .required, .sql(.default(true)))
            .field("approved_at", .datetime)
            .field("approved_by_user_id", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .deleteField("approved_by_user_id")
            .deleteField("approved_at")
            .deleteField("is_approved")
            .deleteField("created_by_user_id")
            .update()
    }
}

struct AddQuestHandoverInfoField: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .field("handover_info", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Quest.schema)
            .deleteField("handover_info")
            .update()
    }
}

struct AddQuestPriorityField: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "SQL database unavailable")
        }
        try await sql.raw("""
            ALTER TABLE quests
            ADD COLUMN IF NOT EXISTS is_prioritized BOOLEAN NOT NULL DEFAULT FALSE
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "SQL database unavailable")
        }
        try await sql.raw("""
            ALTER TABLE quests
            DROP COLUMN IF EXISTS is_prioritized
            """).run()
    }
}
