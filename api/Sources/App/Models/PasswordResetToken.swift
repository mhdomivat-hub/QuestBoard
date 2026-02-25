import Vapor
import Fluent

final class PasswordResetToken: Model, @unchecked Sendable {
    static let schema = "password_reset_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "request_id")
    var request: PasswordResetRequestModel

    @Field(key: "token_hash")
    var tokenHash: String

    @Field(key: "expires_at")
    var expiresAt: Date

    @OptionalField(key: "used_at")
    var usedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, requestID: UUID, tokenHash: String, expiresAt: Date) {
        self.id = id
        self.$request.id = requestID
        self.tokenHash = tokenHash
        self.expiresAt = expiresAt
    }
}

struct CreatePasswordResetToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(PasswordResetToken.schema)
            .id()
            .field("request_id", .uuid, .required, .references(PasswordResetRequestModel.schema, .id, onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("used_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(PasswordResetToken.schema).delete()
    }
}
