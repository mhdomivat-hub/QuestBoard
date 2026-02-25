import Vapor

struct RequirementCreateDTO: Content {
    let itemName: String
    let qtyNeeded: Int
    let unit: String
}

struct RequirementResponseDTO: Content {
    let id: UUID
    let questId: UUID
    let itemName: String
    let qtyNeeded: Int
    let unit: String
    let collectedQty: Int
    let deliveredQty: Int
    let openQty: Int
    let excessQty: Int
}

struct ContributionCreateDTO: Content {
    let qty: Int
    let status: String?
    let note: String?
}

struct ContributionStatusUpdateDTO: Content {
    let status: String
}

struct ContributionUpdateDTO: Content {
    let qty: Int?
    let status: String?
    let note: String?
}

struct ContributionResponseDTO: Content {
    let id: UUID
    let requirementId: UUID
    let userId: UUID
    let username: String
    let qty: Int
    let status: String
    let note: String?
}
