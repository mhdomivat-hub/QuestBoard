import Vapor
import Fluent

final class BlueprintCrafter: Model, @unchecked Sendable {
    static let schema = "blueprint_crafters"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "blueprint_id")
    var blueprint: Blueprint

    @Parent(key: "user_id")
    var user: User

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, blueprintID: UUID, userID: UUID) {
        self.id = id
        self.$blueprint.id = blueprintID
        self.$user.id = userID
    }
}

struct CreateBlueprintCrafter: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(BlueprintCrafter.schema)
            .id()
            .field("blueprint_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("created_at", .datetime)
            .unique(on: "blueprint_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(BlueprintCrafter.schema).delete()
    }
}
