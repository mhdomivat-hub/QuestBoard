import Vapor

struct AdminDataExportDTO: Content {
    let version: Int
    let generatedAt: Date
    let users: [AdminExportUserDTO]
    let quests: [AdminExportQuestDTO]
    let requirements: [AdminExportRequirementDTO]
    let contributions: [AdminExportContributionDTO]
    let passwordResetRequests: [AdminExportPasswordResetRequestDTO]
    let passwordResetTokens: [AdminExportPasswordResetTokenDTO]
    let apiTokens: [AdminExportAPITokenDTO]
    let auditEvents: [AdminExportAuditEventDTO]
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
    let passwordResetRequestsInserted: Int
    let passwordResetRequestsSkipped: Int
    let passwordResetTokensInserted: Int
    let passwordResetTokensSkipped: Int
    let apiTokensInserted: Int
    let apiTokensSkipped: Int
    let auditEventsInserted: Int
    let auditEventsSkipped: Int
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
    let passwordResetRequests: Int
    let passwordResetTokens: Int
    let apiTokens: Int
    let auditEvents: Int
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
