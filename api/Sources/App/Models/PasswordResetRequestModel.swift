import Vapor
import Fluent

enum PasswordResetStatus: String, Codable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case completed = "COMPLETED"
    case rejected = "REJECTED"
}

final class PasswordResetRequestModel: Model, @unchecked Sendable {
    static let schema = "password_reset_requests"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Enum(key: "status")
    var status: PasswordResetStatus

    @OptionalParent(key: "approved_by")
    var approvedBy: User?

    @OptionalField(key: "note")
    var note: String?

    @OptionalField(key: "approved_at")
    var approvedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, userID: UUID, status: PasswordResetStatus, note: String? = nil) {
        self.id = id
        self.$user.id = userID
        self.status = status
        self.note = note
    }
}

struct CreatePasswordResetRequest: AsyncMigration {
    func prepare(on database: Database) async throws {
        let passwordResetStatus = try await database.enum("password_reset_status")
            .case("PENDING")
            .case("APPROVED")
            .case("COMPLETED")
            .case("REJECTED")
            .create()

        try await database.schema(PasswordResetRequestModel.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("status", passwordResetStatus, .required)
            .field("approved_by", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("note", .string)
            .field("approved_at", .datetime)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(PasswordResetRequestModel.schema).delete()
        try await database.enum("password_reset_status").delete()
    }
}
