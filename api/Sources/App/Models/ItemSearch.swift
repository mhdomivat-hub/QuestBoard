import Vapor
import Fluent

enum ItemSearchRequestStatus: String, Codable {
    case open = "OPEN"
    case fulfilled = "FULFILLED"
    case cancelled = "CANCELLED"
}

final class ItemSearchRequest: Model, Content, @unchecked Sendable {
    static let schema = "item_search_requests"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "item_id")
    var item: Blueprint

    @Parent(key: "user_id")
    var user: User

    @OptionalField(key: "average_quality")
    var averageQuality: String?

    @OptionalField(key: "note")
    var note: String?

    @Enum(key: "status")
    var status: ItemSearchRequestStatus

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        itemID: UUID,
        userID: UUID,
        averageQuality: String? = nil,
        note: String? = nil,
        status: ItemSearchRequestStatus = .open
    ) {
        self.id = id
        self.$item.id = itemID
        self.$user.id = userID
        self.averageQuality = averageQuality
        self.note = note
        self.status = status
    }
}

final class ItemSearchOffer: Model, Content, @unchecked Sendable {
    static let schema = "item_search_offers"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "request_id")
    var request: ItemSearchRequest

    @Parent(key: "user_id")
    var user: User

    @OptionalField(key: "note")
    var note: String?

    @Field(key: "has_resources")
    var hasResources: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        requestID: UUID,
        userID: UUID,
        note: String? = nil,
        hasResources: Bool = false
    ) {
        self.id = id
        self.$request.id = requestID
        self.$user.id = userID
        self.note = note
        self.hasResources = hasResources
    }
}

struct CreateItemSearchRequest: AsyncMigration {
    func prepare(on database: Database) async throws {
        let statusEnum = try await database.enum("item_search_request_status")
            .case("OPEN")
            .case("FULFILLED")
            .case("CANCELLED")
            .create()

        try await database.schema(ItemSearchRequest.schema)
            .id()
            .field("item_id", .uuid, .required, .references(Blueprint.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("average_quality", .string)
            .field("note", .string)
            .field("status", statusEnum, .required, .sql(.default("OPEN")))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ItemSearchRequest.schema).delete()
        try await database.enum("item_search_request_status").delete()
    }
}

struct CreateItemSearchOffer: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(ItemSearchOffer.schema)
            .id()
            .field("request_id", .uuid, .required, .references(ItemSearchRequest.schema, .id, onDelete: .cascade))
            .field("user_id", .uuid, .required, .references(User.schema, .id, onDelete: .cascade))
            .field("note", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "request_id", "user_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ItemSearchOffer.schema).delete()
    }
}

struct AddItemSearchOfferHasResources: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(ItemSearchOffer.schema)
            .field("has_resources", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ItemSearchOffer.schema)
            .deleteField("has_resources")
            .update()
    }
}
