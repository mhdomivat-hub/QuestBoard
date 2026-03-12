import Vapor
import Fluent

enum UsernameChangeRequestStatus: String, Codable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
}

final class UsernameChangeRequestModel: Model, @unchecked Sendable {
    static let schema = "username_change_requests"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "current_username")
    var currentUsername: String

    @Field(key: "desired_username")
    var desiredUsername: String

    @Enum(key: "status")
    var status: UsernameChangeRequestStatus

    @OptionalParent(key: "reviewed_by")
    var reviewedBy: User?

    @OptionalField(key: "reviewed_at")
    var reviewedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        currentUsername: String,
        desiredUsername: String,
        status: UsernameChangeRequestStatus = .pending
    ) {
        self.id = id
        self.$user.id = userID
        self.currentUsername = currentUsername
        self.desiredUsername = desiredUsername
        self.status = status
    }
}

struct CreateUsernameChangeRequest: AsyncMigration {
    func prepare(on database: Database) async throws {
        let requestStatus = try await database.enum("username_change_request_status")
            .case("PENDING")
            .case("APPROVED")
            .case("REJECTED")
            .create()

        try await database.schema(UsernameChangeRequestModel.schema)
            .id()
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("current_username", .string, .required)
            .field("desired_username", .string, .required)
            .field("status", requestStatus, .required)
            .field("reviewed_by", .uuid, .references(User.schema, .id, onDelete: .setNull))
            .field("reviewed_at", .datetime)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(UsernameChangeRequestModel.schema).delete()
        try await database.enum("username_change_request_status").delete()
    }
}
