import Vapor
import Fluent
import SQLKit

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "username")
    var username: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Enum(key: "role")
    var role: Role

    enum Role: String, Codable {
        case guest
        case member
        case admin
        case superAdmin
    }

    init() {}

    init(id: UUID? = nil, username: String, passwordHash: String, role: Role = .member) {
        self.id = id
        self.username = username
        self.passwordHash = passwordHash
        self.role = role
    }
}

struct CreateUser: AsyncMigration {
    func prepare(on database: Database) async throws {
        let userRole = try await database.enum("user_role")
            .case("member")
            .case("admin")
            .case("superAdmin")
            .create()

        try await database.schema(User.schema)
            .id()
            .field("username", .string, .required)
            .field("password_hash", .string, .required)
            .field("role", userRole, .required)
            .unique(on: "username")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(User.schema).delete()
        try await database.enum("user_role").delete()
    }
}

struct AddGuestRoleToUserRoleEnum: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'guest'").run()
    }

    func revert(on database: Database) async throws {
        // Enum value rollback is intentionally unsupported for safety.
    }
}
