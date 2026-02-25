import Vapor

public func routes(_ app: Application) throws {
    app.get { _ in "QuestBoard API running" }

    app.post("auth", "login", use: login)
    app.post("auth", "password-reset", "request", use: requestPasswordReset)
    app.post("auth", "password-reset", "confirm", use: confirmPasswordReset)

    let authed = app.grouped(BearerTokenMiddleware())

    authed.get("me", use: me)
    authed.post("auth", "logout", use: logout)
    authed.get("quests", use: listQuests)
    authed.get("quests", ":questID", use: getQuest)
    authed.post("quests", use: createQuest)
    authed.post("quests", ":questID", "approve", use: approveQuest)
    authed.patch("quests", ":questID", "status", use: updateQuestStatus)
    authed.patch("quests", ":questID", "delete", use: markQuestDeleted)
    authed.patch("quests", ":questID", "restore", use: restoreQuest)
    authed.get("quests", ":questID", "requirements", use: listRequirementsForQuest)
    authed.post("quests", ":questID", "requirements", use: createRequirement)
    authed.get("requirements", ":requirementID", "contributions", use: listContributionsForRequirement)
    authed.post("requirements", ":requirementID", "contributions", use: createContribution)
    authed.patch("contributions", ":contributionID", use: updateContribution)
    authed.patch("contributions", ":contributionID", "status", use: updateContributionStatus)

    authed.group("admin") { admin in
        admin.get("password-resets", "pending", use: listPendingPasswordResets)
        admin.post("password-resets", ":requestID", "approve", use: approvePasswordReset)
        admin.post("password-resets", ":requestID", "reject", use: rejectPasswordReset)
        admin.post("retention", "quests", "cleanup", use: cleanupOldQuests)
        admin.get("audit", "events", use: listAuditEvents)
        admin.get("data", "export", use: exportAllData)
        admin.get("data", "export", "manifest", use: exportDataManifest)
        admin.get("data", "export", ":section", use: exportDataSection)
        admin.post("data", "import", use: importAllData)
    }
}
