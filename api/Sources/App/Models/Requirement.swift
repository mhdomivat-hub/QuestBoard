import Vapor
import Fluent

final class Requirement: Model, Content, @unchecked Sendable {
    static let schema = "requirements"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "quest_id")
    var quest: Quest

    @Field(key: "item_name")
    var itemName: String

    @Field(key: "qty_needed")
    var qtyNeeded: Int

    @Field(key: "unit")
    var unit: String

    init() {}

    init(id: UUID? = nil, questID: UUID, itemName: String, qtyNeeded: Int, unit: String) {
        self.id = id
        self.$quest.id = questID
        self.itemName = itemName
        self.qtyNeeded = qtyNeeded
        self.unit = unit
    }
}

struct CreateRequirement: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(Requirement.schema)
            .id()
            .field("quest_id", .uuid, .required, .references(Quest.schema, .id, onDelete: .cascade))
            .field("item_name", .string, .required)
            .field("qty_needed", .int, .required)
            .field("unit", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Requirement.schema).delete()
    }
}
