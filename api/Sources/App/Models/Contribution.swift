import Vapor
import Fluent
import SQLKit

final class Contribution: Model, Content, @unchecked Sendable {
    static let schema = "contributions"

    enum Status: String, Codable {
        case claimed = "CLAIMED"
        case collected = "COLLECTED"
        case delivered = "DELIVERED"
        case cancelled = "CANCELLED"
    }

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "requirement_id")
    var requirement: Requirement

    @Parent(key: "user_id")
    var user: User

    @Field(key: "qty")
    var qty: Int

    @Enum(key: "status")
    var status: Status

    @OptionalField(key: "note")
    var note: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(id: UUID? = nil, requirementID: UUID, userID: UUID, qty: Int, status: Status, note: String? = nil) {
        self.id = id
        self.$requirement.id = requirementID
        self.$user.id = userID
        self.qty = qty
        self.status = status
        self.note = note
    }
}

struct CreateContribution: AsyncMigration {
    func prepare(on database: Database) async throws {
        let contributionStatus = try await database.enum("contribution_status")
            .case("CLAIMED")
            .case("COLLECTED")
            .case("DELIVERED")
            .case("CANCELLED")
            .create()

        try await database.schema(Contribution.schema)
            .id()
            .field("requirement_id", .uuid, .required, .references(Requirement.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("qty", .int, .required)
            .field("status", contributionStatus, .required)
            .field("note", .string)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Contribution.schema).delete()
        try await database.enum("contribution_status").delete()
    }
}

struct AddContributionDeliveredLock: AsyncMigration {
    func prepare(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("""
            CREATE OR REPLACE FUNCTION prevent_delivered_contribution_updates()
            RETURNS trigger AS $$
            BEGIN
                IF OLD.status = 'DELIVERED' THEN
                    RAISE EXCEPTION 'delivered contribution cannot be edited';
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;
            """).run()

        try await sql.raw("""
            DROP TRIGGER IF EXISTS contributions_prevent_delivered_updates ON contributions;
            """).run()

        try await sql.raw("""
            CREATE TRIGGER contributions_prevent_delivered_updates
            BEFORE UPDATE ON contributions
            FOR EACH ROW
            EXECUTE FUNCTION prevent_delivered_contribution_updates();
            """).run()
    }

    func revert(on database: Database) async throws {
        guard let sql = database as? SQLDatabase else { return }
        try await sql.raw("DROP TRIGGER IF EXISTS contributions_prevent_delivered_updates ON contributions;").run()
        try await sql.raw("DROP FUNCTION IF EXISTS prevent_delivered_contribution_updates();").run()
    }
}

