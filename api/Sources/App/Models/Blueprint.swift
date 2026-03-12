import Vapor
import Fluent
import SQLKit

enum BlueprintCategory: String, Codable {
    case blueprints = "BLUEPRINTS"
    case shipsVehicles = "SHIPS_VEHICLES"
    case fps = "FPS"
    case armor = "ARMOR"
    case weapon = "WEAPON"
    case utility = "UTILITY"
    case other = "OTHER"
}

final class Blueprint: Model, Content, @unchecked Sendable {
    static let schema = "blueprints"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "parent_id")
    var parent: Blueprint?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "description")
    var description: String?

    @OptionalField(key: "badges_csv")
    var badgesCSV: String?

    @Enum(key: "category")
    var category: BlueprintCategory

    @Field(key: "is_craftable")
    var isCraftable: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        parentID: UUID? = nil,
        name: String,
        description: String? = nil,
        badgesCSV: String? = nil,
        category: BlueprintCategory,
        isCraftable: Bool
    ) {
        self.id = id
        self.$parent.id = parentID
        self.name = name
        self.description = description
        self.badgesCSV = badgesCSV
        self.category = category
        self.isCraftable = isCraftable
    }
}

struct CreateBlueprint: AsyncMigration {
    func prepare(on database: Database) async throws {
        let categoryEnum = try await database.enum("blueprint_category")
            .case("BLUEPRINTS")
            .case("SHIPS_VEHICLES")
            .case("FPS")
            .case("ARMOR")
            .case("WEAPON")
            .case("UTILITY")
            .case("OTHER")
            .create()

        try await database.schema(Blueprint.schema)
            .id()
            .field("parent_id", .uuid, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("name", .string, .required)
            .field("description", .string)
            .field("badges_csv", .string)
            .field("category", categoryEnum, .required)
            .field("is_craftable", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Blueprint.schema).delete()
        try await database.enum("blueprint_category").delete()
    }
}

struct AddBlueprintTopLevelCategories: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("ALTER TYPE blueprint_category ADD VALUE IF NOT EXISTS 'SHIPS_VEHICLES'").run()
        try await sql.raw("ALTER TYPE blueprint_category ADD VALUE IF NOT EXISTS 'FPS'").run()
        try await sql.raw("""
            UPDATE blueprints
            SET category = 'FPS'::blueprint_category
            WHERE category IN ('ARMOR'::blueprint_category, 'WEAPON'::blueprint_category, 'UTILITY'::blueprint_category, 'OTHER'::blueprint_category)
            """).run()
    }

    func revert(on database: Database) async throws {
        // PostgreSQL enums cannot remove values easily; no-op.
    }
}

struct AddBlueprintUnifiedCategory: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }

        try await sql.raw("ALTER TYPE blueprint_category ADD VALUE IF NOT EXISTS 'BLUEPRINTS'").run()
        try await sql.raw("""
            UPDATE blueprints
            SET category = 'BLUEPRINTS'::blueprint_category
            WHERE category IN (
                'BLUEPRINTS'::blueprint_category,
                'SHIPS_VEHICLES'::blueprint_category,
                'FPS'::blueprint_category,
                'ARMOR'::blueprint_category,
                'WEAPON'::blueprint_category,
                'UTILITY'::blueprint_category,
                'OTHER'::blueprint_category
            )
            """).run()
    }

    func revert(on database: Database) async throws {
        // PostgreSQL enums cannot remove values easily; no-op.
    }
}

struct AddBlueprintBadgesField: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            try await database.schema(Blueprint.schema)
                .field("badges_csv", .string)
                .update()
            return
        }

        try await sql.raw("ALTER TABLE \"\(unsafeRaw: Blueprint.schema)\" ADD COLUMN IF NOT EXISTS \"badges_csv\" TEXT").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            try await database.schema(Blueprint.schema)
                .deleteField("badges_csv")
                .update()
            return
        }

        try await sql.raw("ALTER TABLE \"\(unsafeRaw: Blueprint.schema)\" DROP COLUMN IF EXISTS \"badges_csv\"").run()
    }
}
