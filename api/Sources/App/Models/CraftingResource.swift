import Vapor
import Fluent
import SQLKit

final class BlueprintRecipeResource: Model, Content, @unchecked Sendable {
    static let schema = "blueprint_recipe_resources"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "blueprint_id")
    var blueprint: Blueprint

    @Parent(key: "resource_id")
    var resource: Blueprint

    @Field(key: "slot_name")
    var slotName: String

    @Field(key: "resource_name")
    var resourceName: String

    @Field(key: "quantity")
    var quantity: Double

    @OptionalField(key: "min_quality")
    var minQuality: Int?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, blueprintID: UUID, resourceID: UUID, slotName: String, resourceName: String, quantity: Double, minQuality: Int?) {
        self.id = id
        self.$blueprint.id = blueprintID
        self.$resource.id = resourceID
        self.slotName = slotName
        self.resourceName = resourceName
        self.quantity = quantity
        self.minQuality = minQuality
    }
}

final class StorageEntryResourceUsage: Model, Content, @unchecked Sendable {
    static let schema = "storage_entry_resource_usages"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "entry_id")
    var entry: StorageEntry

    @Parent(key: "resource_id")
    var resource: Blueprint

    @Field(key: "resource_name")
    var resourceName: String

    @Field(key: "quantity")
    var quantity: Double

    @OptionalField(key: "quality")
    var quality: Int?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, entryID: UUID, resourceID: UUID, resourceName: String, quantity: Double, quality: Int?) {
        self.id = id
        self.$entry.id = entryID
        self.$resource.id = resourceID
        self.resourceName = resourceName
        self.quantity = quantity
        self.quality = quality
    }
}

struct CreateBlueprintRecipeResource: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            try await database.schema(BlueprintRecipeResource.schema)
                .id()
                .field("blueprint_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
                .field("resource_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
                .field("slot_name", .string, .required)
                .field("resource_name", .string, .required)
                .field("quantity", .double, .required)
                .field("min_quality", .int)
                .field("created_at", .datetime)
                .create()
            return
        }

        try await sql.raw("""
            CREATE TABLE IF NOT EXISTS "\(unsafeRaw: BlueprintRecipeResource.schema)" (
                "id" UUID PRIMARY KEY,
                "blueprint_id" UUID NOT NULL REFERENCES "\(unsafeRaw: Blueprint.schema)"("id") ON DELETE CASCADE,
                "resource_id" UUID NOT NULL REFERENCES "\(unsafeRaw: Blueprint.schema)"("id") ON DELETE CASCADE,
                "slot_name" TEXT NOT NULL,
                "resource_name" TEXT NOT NULL,
                "quantity" DOUBLE PRECISION NOT NULL,
                "min_quality" INTEGER,
                "created_at" TIMESTAMP WITH TIME ZONE
            )
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema(BlueprintRecipeResource.schema).delete()
    }
}

struct CreateStorageEntryResourceUsage: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            try await database.schema(StorageEntryResourceUsage.schema)
                .id()
                .field("entry_id", .uuid, .required, .references(StorageEntry.schema, .id, onDelete: .cascade))
                .field("resource_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
                .field("resource_name", .string, .required)
                .field("quantity", .double, .required)
                .field("quality", .int)
                .field("created_at", .datetime)
                .create()
            return
        }

        try await sql.raw("""
            CREATE TABLE IF NOT EXISTS "\(unsafeRaw: StorageEntryResourceUsage.schema)" (
                "id" UUID PRIMARY KEY,
                "entry_id" UUID NOT NULL REFERENCES "\(unsafeRaw: StorageEntry.schema)"("id") ON DELETE CASCADE,
                "resource_id" UUID NOT NULL REFERENCES "\(unsafeRaw: Blueprint.schema)"("id") ON DELETE CASCADE,
                "resource_name" TEXT NOT NULL,
                "quantity" DOUBLE PRECISION NOT NULL,
                "quality" INTEGER,
                "created_at" TIMESTAMP WITH TIME ZONE
            )
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema(StorageEntryResourceUsage.schema).delete()
    }
}
