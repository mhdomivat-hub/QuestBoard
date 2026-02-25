import Fluent
import SQLKit
import PostgresKit

struct MigrateQuestStatusToString: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            return
        }

        try await sql.raw("ALTER TABLE quests ALTER COLUMN status TYPE text USING status::text;").run()
        try await sql.raw("DROP TYPE IF EXISTS quest_status;").run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else {
            return
        }

        try await sql.raw("CREATE TYPE quest_status AS ENUM ('OPEN','IN_PROGRESS','DONE','ARCHIVED');").run()
        try await sql.raw("ALTER TABLE quests ALTER COLUMN status TYPE quest_status USING status::quest_status;").run()
    }
}