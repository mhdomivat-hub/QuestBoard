import Vapor

struct BlueprintCreateDTO: Content {
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]?
}

struct BlueprintUpdateDTO: Content {
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let parentId: UUID?
}

struct BlueprintAssignCrafterDTO: Content {
    let userId: UUID?
}

struct BlueprintRenameBadgeDTO: Content {
    let from: String
    let to: String
}

struct BlueprintDeleteBadgeDTO: Content {
    let badge: String
}

struct BlueprintMergeDTO: Content {
    let otherBlueprintId: UUID
    let keepValuesFrom: String
    let parentChoice: String
}

struct BlueprintCrafterResponseDTO: Content {
    let userId: UUID
    let username: String
}

struct BlueprintTreeNodeDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let category: BlueprintCategory
    let isCraftable: Bool
    let crafters: [BlueprintCrafterResponseDTO]
    let children: [BlueprintTreeNodeDTO]
}

struct BlueprintListResponseDTO: Content {
    let blueprints: [BlueprintTreeNodeDTO]
    let availableBadges: [String]
}

struct BlueprintDetailResponseDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let availableBadges: [String]
    let category: BlueprintCategory
    let isCraftable: Bool
    let breadcrumb: [BlueprintBreadcrumbItemDTO]
    let children: [BlueprintChildSummaryDTO]
    let crafters: [BlueprintCrafterResponseDTO]
}

struct BlueprintBreadcrumbItemDTO: Content {
    let id: UUID
    let name: String
}

struct BlueprintChildSummaryDTO: Content {
    let id: UUID
    let name: String
    let itemCode: String?
    let badges: [String]
    let category: BlueprintCategory
    let isCraftable: Bool
    let childCount: Int
    let crafterCount: Int
}
