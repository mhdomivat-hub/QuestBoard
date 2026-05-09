import Vapor

struct QuestCreateDTO: Content {
    let title: String
    let description: String
    let handoverInfo: String?
    let status: String?
    let isPrioritized: Bool?
}

struct QuestStatusUpdateDTO: Content {
    let status: String
}

struct QuestUpdateDTO: Content {
    let title: String
    let description: String
    let handoverInfo: String?
    let isPrioritized: Bool?
}

struct QuestRetentionCleanupRequestDTO: Content {
    let dryRun: Bool?
    let olderThanDays: Int?
}

struct QuestRetentionCleanupResponseDTO: Content {
    let dryRun: Bool
    let olderThanDays: Int
    let cutoff: String
    let candidateCount: Int
    let deletedCount: Int
}

struct QuestResponseDTO: Content {
    let id: UUID
    let title: String
    let description: String
    let handoverInfo: String?
    let status: String
    let createdAt: Date?
    let createdByUserId: UUID?
    let createdByUsername: String?
    let isApproved: Bool
    let approvedAt: Date?
    let isPrioritized: Bool
}
