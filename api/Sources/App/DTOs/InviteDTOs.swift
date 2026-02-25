import Vapor

struct CreateInviteRequestDTO: Content {
    let expiresInHours: Int?
    let maxUses: Int?
}

struct InviteResponseDTO: Content {
    let id: UUID
    let role: User.Role
    let status: String
    let token: String?
    let inviteLink: String?
    let maxUses: Int
    let useCount: Int
    let remainingUses: Int
    let expiresAt: Date
    let createdAt: Date
    let usedAt: Date?
    let revokedAt: Date?
    let createdByUsername: String
}

struct CreateInviteResponseDTO: Content {
    let invite: InviteResponseDTO
    let token: String
    let inviteLink: String
}

struct RegisterByInviteRequestDTO: Content {
    let token: String
    let username: String
    let password: String
}

struct RegisterByInviteResponseDTO: Content {
    let userId: UUID
    let username: String
    let role: User.Role
}
