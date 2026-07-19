import Vapor
import Fluent
import SQLKit

enum LoadoutType: String, Codable {
    case armor = "ARMOR"
    case ship = "SHIP"
}

final class Loadout: Model, Content, @unchecked Sendable {
    static let schema = "loadouts"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "description")
    var description: String?

    @Field(key: "patch_version")
    var patchVersion: String

    @Enum(key: "type")
    var type: LoadoutType

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        description: String? = nil,
        patchVersion: String,
        type: LoadoutType
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.patchVersion = patchVersion
        self.type = type
    }
}

final class LoadoutItem: Model, Content, @unchecked Sendable {
    static let schema = "loadout_items"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "loadout_id")
    var loadout: Loadout

    @Parent(key: "item_id")
    var item: Blueprint

    @OptionalField(key: "slot_name")
    var slotName: String?

    @Field(key: "quantity")
    var quantity: Int

    @Field(key: "sort_order")
    var sortOrder: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        loadoutID: UUID,
        itemID: UUID,
        slotName: String? = nil,
        quantity: Int,
        sortOrder: Int
    ) {
        self.id = id
        self.$loadout.id = loadoutID
        self.$item.id = itemID
        self.slotName = slotName
        self.quantity = quantity
        self.sortOrder = sortOrder
    }
}

final class LoadoutItemMaterialTarget: Model, Content, @unchecked Sendable {
    static let schema = "loadout_item_material_targets"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "loadout_item_id")
    var loadoutItem: LoadoutItem

    @Parent(key: "resource_id")
    var resource: Blueprint

    @Field(key: "slot_name")
    var slotName: String

    @Field(key: "min_quality_key")
    var minQualityKey: Int

    @Field(key: "minimum_quantity")
    var minimumQuantity: Double

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        loadoutItemID: UUID,
        resourceID: UUID,
        slotName: String,
        minQualityKey: Int,
        minimumQuantity: Double
    ) {
        self.id = id
        self.$loadoutItem.id = loadoutItemID
        self.$resource.id = resourceID
        self.slotName = slotName
        self.minQualityKey = minQualityKey
        self.minimumQuantity = minimumQuantity
    }
}

final class LoadoutItemModuleAssignment: Model, Content, @unchecked Sendable {
    static let schema = "loadout_item_module_assignments"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "loadout_item_id")
    var loadoutItem: LoadoutItem

    @OptionalParent(key: "module_item_id")
    var moduleItem: Blueprint?

    @OptionalParent(key: "backup_module_id")
    var backupModule: MiningModuleBackupDefinition?

    @Field(key: "sort_order")
    var sortOrder: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        loadoutItemID: UUID,
        moduleItemID: UUID? = nil,
        backupModuleID: UUID? = nil,
        sortOrder: Int
    ) {
        self.id = id
        self.$loadoutItem.id = loadoutItemID
        self.$moduleItem.id = moduleItemID
        self.$backupModule.id = backupModuleID
        self.sortOrder = sortOrder
    }
}

struct CreateLoadout: AsyncMigration {
    func prepare(on database: Database) async throws {
        if let sql = database as? SQLDatabase {
            let typeEnum = try await database.enum("loadout_type")
                .case("ARMOR")
                .case("SHIP")
                .create()

            try await database.schema(Loadout.schema)
                .id()
                .field("name", .string, .required)
                .field("description", .string)
                .field("patch_version", .string, .required)
                .field("type", typeEnum, .required)
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .create()

            try await database.schema(LoadoutItem.schema)
                .id()
                .field("loadout_id", .uuid, .required, .references(Loadout.schema, .id, onDelete: .cascade))
                .field("item_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
                .field("slot_name", .string)
                .field("quantity", .int, .required, .sql(.default(1)))
                .field("sort_order", .int, .required, .sql(.default(0)))
                .field("created_at", .datetime)
                .field("updated_at", .datetime)
                .unique(on: "loadout_id", "item_id", "slot_name")
                .create()

            _ = sql
            return
        }

        let typeEnum = try await database.enum("loadout_type")
            .case("ARMOR")
            .case("SHIP")
            .create()

        try await database.schema(Loadout.schema)
            .id()
            .field("name", .string, .required)
            .field("description", .string)
            .field("patch_version", .string, .required)
            .field("type", typeEnum, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.schema(LoadoutItem.schema)
            .id()
            .field("loadout_id", .uuid, .required, .references(Loadout.schema, .id, onDelete: .cascade))
            .field("item_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("slot_name", .string)
            .field("quantity", .int, .required, .sql(.default(1)))
            .field("sort_order", .int, .required, .sql(.default(0)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "loadout_id", "item_id", "slot_name")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(LoadoutItem.schema).delete()
        try await database.schema(Loadout.schema).delete()
        try await database.enum("loadout_type").delete()
    }
}

struct AddLoadoutPatchVersion: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            return
        }

        try await sql.raw("ALTER TABLE \"loadouts\" ADD COLUMN IF NOT EXISTS \"patch_version\" TEXT NOT NULL DEFAULT 'unknown'").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            return
        }

        try await sql.raw("ALTER TABLE \"loadouts\" DROP COLUMN IF EXISTS \"patch_version\"").run()
    }
}

struct CreateLoadoutItemMaterialTarget: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(LoadoutItemMaterialTarget.schema)
            .id()
            .field("loadout_item_id", .uuid, .required, .references(LoadoutItem.schema, .id, onDelete: .cascade))
            .field("resource_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("slot_name", .string, .required)
            .field("min_quality_key", .int, .required, .sql(.default(-1)))
            .field("minimum_quantity", .double, .required, .sql(.default(0)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "loadout_item_id", "resource_id", "slot_name", "min_quality_key")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(LoadoutItemMaterialTarget.schema).delete()
    }
}

struct CreateLoadoutItemModuleAssignment: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(LoadoutItemModuleAssignment.schema)
            .id()
            .field("loadout_item_id", .uuid, .required, .references(LoadoutItem.schema, .id, onDelete: .cascade))
            .field("module_item_id", .uuid, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("backup_module_id", .uuid, .references(MiningModuleBackupDefinition.schema, .id, onDelete: .cascade))
            .field("sort_order", .int, .required, .sql(.default(0)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(LoadoutItemModuleAssignment.schema).delete()
    }
}

struct AddBackupMiningModuleSupportToLoadoutAssignments: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            return
        }

        try await sql.raw("ALTER TABLE \"loadout_item_module_assignments\" ADD COLUMN IF NOT EXISTS \"backup_module_id\" UUID REFERENCES \"\(unsafeRaw: MiningModuleBackupDefinition.schema)\"(\"id\") ON DELETE CASCADE").run()
        try await sql.raw("ALTER TABLE \"loadout_item_module_assignments\" ALTER COLUMN \"module_item_id\" DROP NOT NULL").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            return
        }

        try await sql.raw("ALTER TABLE \"loadout_item_module_assignments\" DROP COLUMN IF EXISTS \"backup_module_id\"").run()
    }
}

