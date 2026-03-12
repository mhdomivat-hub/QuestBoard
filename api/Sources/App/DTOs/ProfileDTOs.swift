import Vapor

struct UsernameChangeRequestSummaryDTO: Content {
    let id: UUID
    let desiredUsername: String
    let status: UsernameChangeRequestStatus
    let createdAt: Date?
    let reviewedAt: Date?
}

struct AccountResponseDTO: Content {
    let userId: UUID
    let username: String
    let role: User.Role
    let pendingUsernameChangeRequest: UsernameChangeRequestSummaryDTO?
}

struct ChangeOwnPasswordRequestDTO: Content {
    let currentPassword: String
    let newPassword: String
}

struct CreateUsernameChangeRequestDTO: Content {
    let desiredUsername: String
}

struct AdminUsernameChangeRequestDTO: Content {
    let id: UUID
    let userId: UUID
    let currentUsername: String
    let desiredUsername: String
    let status: UsernameChangeRequestStatus
    let createdAt: Date?
    let reviewedAt: Date?
}
