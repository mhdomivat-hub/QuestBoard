import Vapor
import Fluent
import FluentPostgresDriver

public func configure(_ app: Application) throws {
    guard let dbURL = Environment.get("DATABASE_URL") else {
        app.logger.critical("DATABASE_URL missing")
        throw Abort(.internalServerError, reason: "DATABASE_URL missing")
    }

    try app.databases.use(.postgres(url: dbURL), as: .psql)

    app.middleware.use(RequestContextMiddleware())

    app.migrations.add(CreateUser())
    app.migrations.add(AddGuestRoleToUserRoleEnum())
    app.migrations.add(CreateAuditEvent())
    app.migrations.add(CreateAPIToken())
    app.migrations.add(CreateQuest())
    app.migrations.add(AddQuestRetentionFields())
    app.migrations.add(AddQuestApprovalFields())
    app.migrations.add(AddQuestHandoverInfoField())
    app.migrations.add(AddQuestPriorityField())
    app.migrations.add(MigrateQuestStatusToString())
    app.migrations.add(CreateRequirement())
    app.migrations.add(CreateContribution())
    app.migrations.add(AddContributionDeliveredLock())
    app.migrations.add(CreatePasswordResetRequest())
    app.migrations.add(CreatePasswordResetToken())
    app.migrations.add(CreateUsernameChangeRequest())
    app.migrations.add(CreateInvite())
    app.migrations.add(AddInviteRawTokenField())
    app.migrations.add(AddInviteUsageFields())
    app.migrations.add(CreateBlueprint())
    app.migrations.add(AddBlueprintTopLevelCategories())
    app.migrations.add(AddBlueprintUnifiedCategory())
    app.migrations.add(AddBlueprintBadgesField())
    app.migrations.add(AddBlueprintItemCodeField())
    app.migrations.add(AddBlueprintHideFromBlueprintsField())
    app.migrations.add(CreateItemBadgeDefinition())
    app.migrations.add(CreateBlueprintCrafter())
    app.migrations.add(CreateStorageLocation())
    app.migrations.add(CreateStorageEntry())
    app.migrations.add(MigrateStorageItemsToBlueprintItems())
    app.migrations.add(CreateItemSearchRequest())
    app.migrations.add(CreateItemSearchOffer())
    app.migrations.add(CreateQuestTemplate())
    app.migrations.add(CreateQuestTemplateRequirement())

    try app.autoMigrate().wait()
    try app.eventLoopGroup.next().makeFutureWithTask {
        try await bootstrapInitialAdmin(app)
    }.wait()

    try routes(app)
}

