import Vapor
import Fluent

final class ItemBadgeDefinition: Model, Content, @unchecked Sendable {
    static let schema = "item_badge_definitions"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "group_name")
    var groupName: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, groupName: String? = nil) {
        self.id = id
        self.name = name
        self.groupName = groupName
    }
}

struct CreateItemBadgeDefinition: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(ItemBadgeDefinition.schema)
            .id()
            .field("name", .string, .required)
            .field("group_name", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ItemBadgeDefinition.schema).delete()
    }
}
