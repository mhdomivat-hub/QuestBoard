import Vapor
import Fluent
import SQLKit

final class StorageLocation: Model, Content, @unchecked Sendable {
    static let schema = "storage_locations"

    @ID(key: .id)
    var id: UUID?

    @OptionalParent(key: "parent_id")
    var parent: StorageLocation?

    @Field(key: "name")
    var name: String

    @OptionalField(key: "description")
    var description: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, parentID: UUID? = nil, name: String, description: String? = nil) {
        self.id = id
        self.$parent.id = parentID
        self.name = name
        self.description = description
    }
}

final class StorageEntry: Model, Content, @unchecked Sendable {
    static let schema = "storage_entries"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "item_id")
    var item: Blueprint

    @Parent(key: "location_id")
    var location: StorageLocation

    @Parent(key: "user_id")
    var user: User

    @Field(key: "qty")
    var qty: Int

    @OptionalField(key: "note")
    var note: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, itemID: UUID, locationID: UUID, userID: UUID, qty: Int, note: String? = nil) {
        self.id = id
        self.$item.id = itemID
        self.$location.id = locationID
        self.$user.id = userID
        self.qty = qty
        self.note = note
    }
}

struct CreateStorageLocation: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(StorageLocation.schema)
            .id()
            .field("parent_id", .uuid, .references(StorageLocation.schema, .id, onDelete: .cascade))
            .field("name", .string, .required)
            .field("description", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(StorageLocation.schema).delete()
    }
}

struct CreateStorageEntry: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(StorageEntry.schema)
            .id()
            .field("item_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("location_id", .uuid, .required, .references(StorageLocation.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("qty", .int, .required)
            .field("note", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(StorageEntry.schema).delete()
    }
}

private func storageTableExists(sql: SQLDatabase, tableName: String) async throws -> Bool {
    let rows = try await sql.raw(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = current_schema() AND table_name = \(bind: tableName) LIMIT 1"
    ).all()
    return !rows.isEmpty
}

struct MigrateStorageItemsToBlueprintItems: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        guard try await storageTableExists(sql: sql, tableName: StorageEntry.schema) else { return }

        try await sql.raw("ALTER TABLE \"\(unsafeRaw: StorageEntry.schema)\" DROP CONSTRAINT IF EXISTS \"storage_entries_item_id_fkey\"").run()

        if try await storageTableExists(sql: sql, tableName: "storage_items") {
            try await sql.raw("DELETE FROM \"\(unsafeRaw: StorageEntry.schema)\"").run()
            try await sql.raw("DROP TABLE IF EXISTS \"storage_items\" CASCADE").run()
        }

        try await sql.raw("""
            ALTER TABLE "\(unsafeRaw: StorageEntry.schema)"
            ADD CONSTRAINT "storage_entries_item_id_fkey"
            FOREIGN KEY ("item_id") REFERENCES "\(unsafeRaw: Blueprint.schema)"("id") ON DELETE CASCADE
            """).run()
    }

    func revert(on database: Database) async throws {
        // No rollback: storage item data was explicitly dropped during consolidation.
    }
}
