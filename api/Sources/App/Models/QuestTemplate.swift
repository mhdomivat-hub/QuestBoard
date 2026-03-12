import Vapor
import Fluent

final class QuestTemplate: Model, Content, @unchecked Sendable {
    static let schema = "quest_templates"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @Field(key: "description")
    var description: String

    @OptionalField(key: "handover_info")
    var handoverInfo: String?

    @OptionalParent(key: "source_quest_id")
    var sourceQuest: Quest?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, title: String, description: String, handoverInfo: String? = nil, sourceQuestId: UUID? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.handoverInfo = handoverInfo
        self.$sourceQuest.id = sourceQuestId
    }
}

final class QuestTemplateRequirement: Model, Content, @unchecked Sendable {
    static let schema = "quest_template_requirements"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "template_id")
    var template: QuestTemplate

    @Field(key: "item_name")
    var itemName: String

    @Field(key: "qty_needed")
    var qtyNeeded: Int

    @Field(key: "unit")
    var unit: String

    init() {}

    init(id: UUID? = nil, templateId: UUID, itemName: String, qtyNeeded: Int, unit: String) {
        self.id = id
        self.$template.id = templateId
        self.itemName = itemName
        self.qtyNeeded = qtyNeeded
        self.unit = unit
    }
}

struct CreateQuestTemplate: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(QuestTemplate.schema)
            .id()
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("handover_info", .string)
            .field("source_quest_id", .uuid, .references(Quest.schema, .id, onDelete: .setNull))
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(QuestTemplate.schema).delete()
    }
}

struct CreateQuestTemplateRequirement: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(QuestTemplateRequirement.schema)
            .id()
            .field("template_id", .uuid, .required, .references(QuestTemplate.schema, .id, onDelete: .cascade))
            .field("item_name", .string, .required)
            .field("qty_needed", .int, .required)
            .field("unit", .string, .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(QuestTemplateRequirement.schema).delete()
    }
}
