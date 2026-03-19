import Vapor

struct AdminDataExportDTO: Content {
    let version: Int
    let generatedAt: Date
    let users: [AdminExportUserDTO]
    let quests: [AdminExportQuestDTO]
    let requirements: [AdminExportRequirementDTO]
    let contributions: [AdminExportContributionDTO]
    let blueprints: [AdminExportBlueprintDTO]
    let blueprintCrafters: [AdminExportBlueprintCrafterDTO]
    let storageLocations: [AdminExportStorageLocationDTO]
    let storageEntries: [AdminExportStorageEntryDTO]
    let invites: [AdminExportInviteDTO]
    let usernameChangeRequests: [AdminExportUsernameChangeRequestDTO]
    let questTemplates: [AdminExportQuestTemplateDTO]
    let questTemplateRequirements: [AdminExportQuestTemplateRequirementDTO]
    let passwordResetRequests: [AdminExportPasswordResetRequestDTO]
    let passwordResetTokens: [AdminExportPasswordResetTokenDTO]
    let apiTokens: [AdminExportAPITokenDTO]
    let auditEvents: [AdminExportAuditEventDTO]

    init(
        version: Int,
        generatedAt: Date,
        users: [AdminExportUserDTO],
        quests: [AdminExportQuestDTO],
        requirements: [AdminExportRequirementDTO],
        contributions: [AdminExportContributionDTO],
        blueprints: [AdminExportBlueprintDTO] = [],
        blueprintCrafters: [AdminExportBlueprintCrafterDTO] = [],
        storageLocations: [AdminExportStorageLocationDTO] = [],
        storageEntries: [AdminExportStorageEntryDTO] = [],
        invites: [AdminExportInviteDTO] = [],
        usernameChangeRequests: [AdminExportUsernameChangeRequestDTO] = [],
        questTemplates: [AdminExportQuestTemplateDTO] = [],
        questTemplateRequirements: [AdminExportQuestTemplateRequirementDTO] = [],
        passwordResetRequests: [AdminExportPasswordResetRequestDTO],
        passwordResetTokens: [AdminExportPasswordResetTokenDTO],
        apiTokens: [AdminExportAPITokenDTO],
        auditEvents: [AdminExportAuditEventDTO]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.users = users
        self.quests = quests
        self.requirements = requirements
        self.contributions = contributions
        self.blueprints = blueprints
        self.blueprintCrafters = blueprintCrafters
        self.storageLocations = storageLocations
        self.storageEntries = storageEntries
        self.invites = invites
        self.usernameChangeRequests = usernameChangeRequests
        self.questTemplates = questTemplates
        self.questTemplateRequirements = questTemplateRequirements
        self.passwordResetRequests = passwordResetRequests
        self.passwordResetTokens = passwordResetTokens
        self.apiTokens = apiTokens
        self.auditEvents = auditEvents
    }
}

struct AdminDataImportResultDTO: Content {
    let usersInserted: Int
    let usersSkipped: Int
    let questsInserted: Int
    let questsSkipped: Int
    let requirementsInserted: Int
    let requirementsSkipped: Int
    let contributionsInserted: Int
    let contributionsSkipped: Int
    let blueprintsInserted: Int
    let blueprintsSkipped: Int
    let blueprintCraftersInserted: Int
    let blueprintCraftersSkipped: Int
    let storageLocationsInserted: Int
    let storageLocationsSkipped: Int
    let storageEntriesInserted: Int
    let storageEntriesSkipped: Int
    let invitesInserted: Int
    let invitesSkipped: Int
    let usernameChangeRequestsInserted: Int
    let usernameChangeRequestsSkipped: Int
    let questTemplatesInserted: Int
    let questTemplatesSkipped: Int
    let questTemplateRequirementsInserted: Int
    let questTemplateRequirementsSkipped: Int
    let passwordResetRequestsInserted: Int
    let passwordResetRequestsSkipped: Int
    let passwordResetTokensInserted: Int
    let passwordResetTokensSkipped: Int
    let apiTokensInserted: Int
    let apiTokensSkipped: Int
    let auditEventsInserted: Int
    let auditEventsSkipped: Int

    init(
        usersInserted: Int,
        usersSkipped: Int,
        questsInserted: Int,
        questsSkipped: Int,
        requirementsInserted: Int,
        requirementsSkipped: Int,
        contributionsInserted: Int,
        contributionsSkipped: Int,
        blueprintsInserted: Int = 0,
        blueprintsSkipped: Int = 0,
        blueprintCraftersInserted: Int = 0,
        blueprintCraftersSkipped: Int = 0,
        storageLocationsInserted: Int = 0,
        storageLocationsSkipped: Int = 0,
        storageEntriesInserted: Int = 0,
        storageEntriesSkipped: Int = 0,
        invitesInserted: Int = 0,
        invitesSkipped: Int = 0,
        usernameChangeRequestsInserted: Int = 0,
        usernameChangeRequestsSkipped: Int = 0,
        questTemplatesInserted: Int = 0,
        questTemplatesSkipped: Int = 0,
        questTemplateRequirementsInserted: Int = 0,
        questTemplateRequirementsSkipped: Int = 0,
        passwordResetRequestsInserted: Int,
        passwordResetRequestsSkipped: Int,
        passwordResetTokensInserted: Int,
        passwordResetTokensSkipped: Int,
        apiTokensInserted: Int,
        apiTokensSkipped: Int,
        auditEventsInserted: Int,
        auditEventsSkipped: Int
    ) {
        self.usersInserted = usersInserted
        self.usersSkipped = usersSkipped
        self.questsInserted = questsInserted
        self.questsSkipped = questsSkipped
        self.requirementsInserted = requirementsInserted
        self.requirementsSkipped = requirementsSkipped
        self.contributionsInserted = contributionsInserted
        self.contributionsSkipped = contributionsSkipped
        self.blueprintsInserted = blueprintsInserted
        self.blueprintsSkipped = blueprintsSkipped
        self.blueprintCraftersInserted = blueprintCraftersInserted
        self.blueprintCraftersSkipped = blueprintCraftersSkipped
        self.storageLocationsInserted = storageLocationsInserted
        self.storageLocationsSkipped = storageLocationsSkipped
        self.storageEntriesInserted = storageEntriesInserted
        self.storageEntriesSkipped = storageEntriesSkipped
        self.invitesInserted = invitesInserted
        self.invitesSkipped = invitesSkipped
        self.usernameChangeRequestsInserted = usernameChangeRequestsInserted
        self.usernameChangeRequestsSkipped = usernameChangeRequestsSkipped
        self.questTemplatesInserted = questTemplatesInserted
        self.questTemplatesSkipped = questTemplatesSkipped
        self.questTemplateRequirementsInserted = questTemplateRequirementsInserted
        self.questTemplateRequirementsSkipped = questTemplateRequirementsSkipped
        self.passwordResetRequestsInserted = passwordResetRequestsInserted
        self.passwordResetRequestsSkipped = passwordResetRequestsSkipped
        self.passwordResetTokensInserted = passwordResetTokensInserted
        self.passwordResetTokensSkipped = passwordResetTokensSkipped
        self.apiTokensInserted = apiTokensInserted
        self.apiTokensSkipped = apiTokensSkipped
        self.auditEventsInserted = auditEventsInserted
        self.auditEventsSkipped = auditEventsSkipped
    }
}

struct AdminRemoteTransferRequestDTO: Content {
    let sourceBaseURL: String
    let sourceToken: String
    let sections: [String]?
}

struct AdminRemoteTransferResultDTO: Content {
    let manifest: AdminDataExportManifestDTO
    let chunksFetched: Int
    let sections: [String]
    let importResult: AdminDataImportResultDTO
}

struct AdminRemotePushRequestDTO: Content {
    let targetBaseURL: String
    let targetToken: String
    let sections: [String]?
}

struct AdminRemotePushResultDTO: Content {
    let manifest: AdminDataExportManifestDTO
    let chunksSent: Int
    let sections: [String]
    let importResult: AdminDataImportResultDTO
}

struct AdminDataExportManifestDTO: Content {
    let version: Int
    let generatedAt: Date
    let counts: AdminDataExportManifestCountsDTO
}

struct AdminDataExportManifestCountsDTO: Content {
    let users: Int
    let quests: Int
    let requirements: Int
    let contributions: Int
    let blueprints: Int
    let blueprintCrafters: Int
    let storageLocations: Int
    let storageEntries: Int
    let invites: Int
    let usernameChangeRequests: Int
    let questTemplates: Int
    let questTemplateRequirements: Int
    let passwordResetRequests: Int
    let passwordResetTokens: Int
    let apiTokens: Int
    let auditEvents: Int

    init(
        users: Int,
        quests: Int,
        requirements: Int,
        contributions: Int,
        blueprints: Int = 0,
        blueprintCrafters: Int = 0,
        storageLocations: Int = 0,
        storageEntries: Int = 0,
        invites: Int = 0,
        usernameChangeRequests: Int = 0,
        questTemplates: Int = 0,
        questTemplateRequirements: Int = 0,
        passwordResetRequests: Int,
        passwordResetTokens: Int,
        apiTokens: Int,
        auditEvents: Int
    ) {
        self.users = users
        self.quests = quests
        self.requirements = requirements
        self.contributions = contributions
        self.blueprints = blueprints
        self.blueprintCrafters = blueprintCrafters
        self.storageLocations = storageLocations
        self.storageEntries = storageEntries
        self.invites = invites
        self.usernameChangeRequests = usernameChangeRequests
        self.questTemplates = questTemplates
        self.questTemplateRequirements = questTemplateRequirements
        self.passwordResetRequests = passwordResetRequests
        self.passwordResetTokens = passwordResetTokens
        self.apiTokens = apiTokens
        self.auditEvents = auditEvents
    }
}

struct AdminExportUserDTO: Content {
    let id: UUID
    let username: String
    let passwordHash: String
    let role: String
}

struct AdminExportQuestDTO: Content {
    let id: UUID
    let title: String
    let description: String
    let handoverInfo: String?
    let status: String
    let terminalSinceAt: Date?
    let deletedAt: Date?
    let createdAt: Date?
    let createdByUserId: UUID?
    let isApproved: Bool
    let approvedAt: Date?
    let approvedByUserId: UUID?
    let isPrioritized: Bool
}

struct AdminExportRequirementDTO: Content {
    let id: UUID
    let questId: UUID
    let itemName: String
    let qtyNeeded: Int
    let unit: String
}

struct AdminExportContributionDTO: Content {
    let id: UUID
    let requirementId: UUID
    let userId: UUID
    let qty: Int
    let status: String
    let note: String?
    let createdAt: Date?
}

struct AdminExportBlueprintDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badgesCSV: String?
    let category: String
    let isCraftable: Bool
    let createdAt: Date?
    let updatedAt: Date?
}

struct AdminExportBlueprintCrafterDTO: Content {
    let id: UUID
    let blueprintId: UUID
    let userId: UUID
    let createdAt: Date?
}

struct AdminExportStorageLocationDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct AdminExportStorageEntryDTO: Content {
    let id: UUID
    let itemId: UUID
    let locationId: UUID
    let userId: UUID
    let qty: Int
    let note: String?
    let createdAt: Date?
}

struct AdminExportInviteDTO: Content {
    let id: UUID
    let tokenHash: String
    let rawToken: String?
    let role: String
    let maxUses: Int
    let useCount: Int
    let createdByUserId: UUID
    let usedByUserId: UUID?
    let expiresAt: Date
    let usedAt: Date?
    let revokedAt: Date?
    let createdAt: Date
}

struct AdminExportUsernameChangeRequestDTO: Content {
    let id: UUID
    let userId: UUID
    let currentUsername: String
    let desiredUsername: String
    let status: String
    let reviewedBy: UUID?
    let reviewedAt: Date?
    let createdAt: Date?
}

struct AdminExportQuestTemplateDTO: Content {
    let id: UUID
    let title: String
    let description: String
    let handoverInfo: String?
    let sourceQuestId: UUID?
    let createdAt: Date?
}

struct AdminExportQuestTemplateRequirementDTO: Content {
    let id: UUID
    let templateId: UUID
    let itemName: String
    let qtyNeeded: Int
    let unit: String
}

struct AdminExportPasswordResetRequestDTO: Content {
    let id: UUID
    let userId: UUID
    let status: String
    let approvedBy: UUID?
    let note: String?
    let approvedAt: Date?
    let createdAt: Date?
}

struct AdminExportPasswordResetTokenDTO: Content {
    let id: UUID
    let requestId: UUID
    let tokenHash: String
    let expiresAt: Date
    let usedAt: Date?
    let createdAt: Date?
}

struct AdminExportAPITokenDTO: Content {
    let id: UUID
    let userId: UUID
    let tokenHash: String
    let expiresAt: Date
    let createdAt: Date?
}

struct AdminExportAuditEventDTO: Content {
    let id: UUID
    let actorUserId: UUID?
    let actorUsername: String
    let action: String
    let entityType: String
    let entityId: UUID?
    let details: String?
    let createdAt: Date?
}
