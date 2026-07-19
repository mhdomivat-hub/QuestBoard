import Vapor
import Fluent
import SQLKit

enum LoadoutBackupModuleType: String, Codable, CaseIterable {
    case miningLaser = "MINING_LASER"
    case fpsWeapon = "FPS_WEAPON"
}

final class MiningModuleBackupDefinition: Model, Content, @unchecked Sendable {
    static let schema = "mining_module_backup_definitions"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    @Enum(key: "module_type")
    var moduleType: LoadoutBackupModuleType

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, name: String, moduleType: LoadoutBackupModuleType) {
        self.id = id
        self.name = name
        self.moduleType = moduleType
    }
}

struct CreateMiningModuleBackupDefinition: AsyncMigration {
    func prepare(on database: Database) async throws {
        let typeEnum = try await database.enum("loadout_backup_module_type")
            .case(LoadoutBackupModuleType.miningLaser.rawValue)
            .case(LoadoutBackupModuleType.fpsWeapon.rawValue)
            .create()

        try await database.schema(MiningModuleBackupDefinition.schema)
            .id()
            .field("name", .string, .required)
            .field("module_type", typeEnum, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "name")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(MiningModuleBackupDefinition.schema).delete()
        try await database.enum("loadout_backup_module_type").delete()
    }
}

struct AddModuleTypeToMiningModuleBackupDefinition: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            return
        }

        let rows = try await sql.raw("SELECT 1 FROM pg_type WHERE typname = 'loadout_backup_module_type' LIMIT 1").all()
        if rows.isEmpty {
            _ = try await database.enum("loadout_backup_module_type")
                .case(LoadoutBackupModuleType.miningLaser.rawValue)
                .case(LoadoutBackupModuleType.fpsWeapon.rawValue)
                .create()
        }

        try await sql.raw("ALTER TABLE \"mining_module_backup_definitions\" ADD COLUMN IF NOT EXISTS \"module_type\" loadout_backup_module_type NOT NULL DEFAULT 'MINING_LASER'").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            return
        }

        try await sql.raw("ALTER TABLE \"mining_module_backup_definitions\" DROP COLUMN IF EXISTS \"module_type\"").run()
    }
}
