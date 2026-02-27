import Vapor
import SQLKit

struct QuestAccessContext {
    let id: UUID
    let createdByUserId: UUID?
    let isApproved: Bool
    let status: String
}

func isAdminRole(_ role: User.Role) -> Bool {
    role == .admin || role == .superAdmin
}

func canReadQuest(user: User, quest: QuestAccessContext) -> Bool {
    guard let userId = user.id else { return false }
    if isAdminRole(user.role) {
        return true
    }
    return quest.isApproved || quest.createdByUserId == userId
}

func canEditQuest(user: User, quest: QuestAccessContext) -> Bool {
    guard let userId = user.id else { return false }
    if quest.isApproved {
        return isAdminRole(user.role)
    }
    return isAdminRole(user.role) || quest.createdByUserId == userId
}

func canEditQuestDetails(user: User, quest: QuestAccessContext) -> Bool {
    guard let userId = user.id else { return false }
    if isAdminRole(user.role) {
        return true
    }
    return quest.createdByUserId == userId && !quest.isApproved && quest.status == Quest.Status.open.rawValue
}

func loadQuestAccessContext(sql: SQLDatabase, questID: UUID) async throws -> QuestAccessContext? {
    let rows = try await sql.raw("""
        SELECT id, created_by_user_id, is_approved, status
        FROM quests
        WHERE id = \(bind: questID)
        LIMIT 1
        """).all()
    guard let row = rows.first else { return nil }

    let id: UUID = try row.decode(column: "id", as: UUID.self)
    let createdByUserId: UUID? = try row.decodeNil(column: "created_by_user_id")
        ? nil
        : row.decode(column: "created_by_user_id", as: UUID.self)
    let isApproved: Bool = try row.decode(column: "is_approved", as: Bool.self)
    let status: String = try row.decode(column: "status", as: String.self)
    return .init(id: id, createdByUserId: createdByUserId, isApproved: isApproved, status: status)
}
