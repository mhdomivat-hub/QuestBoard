import Vapor

struct PasswordResetRequestCreateDTO: Content {
    let username: String
    let note: String?
}

struct PasswordResetAdminListItemDTO: Content {
    let id: UUID
    let username: String
    let status: PasswordResetStatus
    let createdAt: Date?
    let note: String?
}

struct PasswordResetApproveResponseDTO: Content {
    let requestId: UUID
    let resetLink: String
    let expiresAt: Date
}

struct PasswordResetConfirmDTO: Content {
    let token: String
    let newPassword: String
}
