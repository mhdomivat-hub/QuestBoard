import Vapor

struct AdminUserDTO: Content {
    let id: UUID
    let username: String
    let role: User.Role
    let isRoleImmutable: Bool
}

struct UpdateUserRoleRequestDTO: Content {
    let role: User.Role
}
