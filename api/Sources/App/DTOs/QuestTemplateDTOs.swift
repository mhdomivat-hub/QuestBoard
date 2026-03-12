import Vapor

struct QuestTemplateCreateDTO: Content {
    let title: String
    let description: String
    let handoverInfo: String?
}

struct QuestTemplateUpdateDTO: Content {
    let title: String
    let description: String
    let handoverInfo: String?
}

struct QuestTemplateRequirementCreateDTO: Content {
    let itemName: String
    let qtyNeeded: Int
    let unit: String
}

struct QuestTemplateRequirementResponseDTO: Content {
    let id: UUID
    let templateId: UUID
    let itemName: String
    let qtyNeeded: Int
    let unit: String
}

struct QuestTemplateSummaryDTO: Content {
    let id: UUID
    let title: String
    let description: String
    let handoverInfo: String?
    let sourceQuestId: UUID?
    let requirementCount: Int
    let createdAt: Date?
}

struct QuestTemplateDetailDTO: Content {
    let id: UUID
    let title: String
    let description: String
    let handoverInfo: String?
    let sourceQuestId: UUID?
    let createdAt: Date?
    let requirements: [QuestTemplateRequirementResponseDTO]
}
