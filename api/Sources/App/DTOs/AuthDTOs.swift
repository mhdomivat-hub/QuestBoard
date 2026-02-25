import Vapor

struct LoginRequestDTO: Content {
    let username: String
    let password: String
}

struct LoginResponseDTO: Content {
    let token: String
    let userId: UUID
    let username: String
    let role: User.Role
}

struct MeResponseDTO: Content {
    let userId: UUID
    let username: String
    let role: User.Role
}
