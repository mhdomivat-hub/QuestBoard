import Vapor
import Fluent
import FluentSQL

final class Invite: Model, Content, @unchecked Sendable {
    static let schema = "invites"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "token_hash")
    var tokenHash: String

    @OptionalField(key: "raw_token")
    var rawToken: String?

    @Field(key: "role")
    var role: String

    @Field(key: "max_uses")
    var maxUses: Int

    @Field(key: "use_count")
    var useCount: Int

    @Parent(key: "created_by_user_id")
    var createdBy: User

    @OptionalParent(key: "used_by_user_id")
    var usedBy: User?

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "used_at")
    var usedAt: Date?

    @OptionalField(key: "revoked_at")
    var revokedAt: Date?

    @Field(key: "created_at")
    var createdAt: Date

    init() {}

    init(
        id: UUID? = nil,
        tokenHash: String,
        rawToken: String? = nil,
        role: String,
        maxUses: Int = 1,
        useCount: Int = 0,
        createdByUserID: UUID,
        expiresAt: Date,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.tokenHash = tokenHash
        self.rawToken = rawToken
        self.role = role
        self.maxUses = maxUses
        self.useCount = useCount
        self.$createdBy.id = createdByUserID
        self.expiresAt = expiresAt
        self.createdAt = createdAt
    }
}

struct CreateInvite: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Invite.schema)
            .id()
            .field("token_hash", .string, .required)
            .field("role", .string, .required)
            .field("created_by_user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("used_by_user_id", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .field("revoked_at", .datetime)
            .field("created_at", .datetime, .required)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Invite.schema).delete()
    }
}

struct AddInviteRawTokenField: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Invite.schema)
            .field("raw_token", .string)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Invite.schema)
            .deleteField("raw_token")
            .update()
    }
}

struct AddInviteUsageFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Invite.schema)
            .field("max_uses", .int, .required, .sql(.default(1)))
            .field("use_count", .int, .required, .sql(.default(0)))
            .update()

        if let sql = database as? SQLDatabase {
            try await sql.raw(
                "UPDATE \(unsafeRaw: Invite.schema) SET use_count = CASE WHEN used_at IS NULL THEN 0 ELSE 1 END WHERE use_count = 0"
            ).run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema(Invite.schema)
            .deleteField("max_uses")
            .deleteField("use_count")
            .update()
    }
}
