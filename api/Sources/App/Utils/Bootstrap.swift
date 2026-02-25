import Vapor
import Fluent

func bootstrapInitialAdmin(_ app: Application) async throws {
    guard
        let username = Environment.get("BOOTSTRAP_ADMIN_USERNAME"),
        let password = Environment.get("BOOTSTRAP_ADMIN_PASSWORD"),
        !username.isEmpty,
        !password.isEmpty
    else {
        app.logger.info("Bootstrap admin skipped: BOOTSTRAP_ADMIN_USERNAME/BOOTSTRAP_ADMIN_PASSWORD not set")
        return
    }

    let existing = try await User.query(on: app.db)
        .filter(\.$username == username)
        .first()

    if existing == nil {
        let hash = try hashPassword(password)
        let admin = User(username: username, passwordHash: hash, role: .superAdmin)
        try await admin.save(on: app.db)
        app.logger.info("Bootstrap admin created with username: \(username)")
    }

    guard
        let memberUsername = Environment.get("BOOTSTRAP_MEMBER_USERNAME"),
        let memberPassword = Environment.get("BOOTSTRAP_MEMBER_PASSWORD"),
        !memberUsername.isEmpty,
        !memberPassword.isEmpty
    else {
        app.logger.info("Bootstrap member skipped: BOOTSTRAP_MEMBER_USERNAME/BOOTSTRAP_MEMBER_PASSWORD not set")
        return
    }

    let existingMember = try await User.query(on: app.db)
        .filter(\.$username == memberUsername)
        .first()

    if existingMember == nil {
        let memberHash = try hashPassword(memberPassword)
        let member = User(username: memberUsername, passwordHash: memberHash, role: .member)
        try await member.save(on: app.db)
        app.logger.info("Bootstrap member created with username: \(memberUsername)")
    }
}
