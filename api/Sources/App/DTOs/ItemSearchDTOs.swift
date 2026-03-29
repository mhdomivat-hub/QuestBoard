import Vapor

struct ItemSearchRequestCreateDTO: Content {
    let averageQuality: String?
    let note: String?
}

struct ItemSearchRequestStatusUpdateDTO: Content {
    let status: ItemSearchRequestStatus
}

struct ItemSearchOfferCreateDTO: Content {
    let note: String?
    let hasResources: Bool?
}

struct ItemSearchOfferResponseDTO: Content {
    let id: UUID
    let userId: UUID
    let username: String
    let note: String?
    let hasResources: Bool
    let createdAt: Date?
}

struct ItemSearchRequestResponseDTO: Content {
    let id: UUID
    let userId: UUID
    let username: String
    let averageQuality: String?
    let note: String?
    let status: ItemSearchRequestStatus
    let createdAt: Date?
    let offers: [ItemSearchOfferResponseDTO]
}

struct ItemSearchTreeNodeDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let openRequestCount: Int
    let offerCount: Int
    let crafterCount: Int
    let totalQty: Int
    let children: [ItemSearchTreeNodeDTO]
}

struct ItemSearchListResponseDTO: Content {
    let items: [ItemSearchTreeNodeDTO]
    let availableBadges: [String]
}

struct ItemSearchBreadcrumbItemDTO: Content {
    let id: UUID
    let name: String
}

struct ItemSearchChildSummaryDTO: Content {
    let id: UUID
    let name: String
    let itemCode: String?
    let badges: [String]
    let openRequestCount: Int
    let offerCount: Int
}

struct ItemSearchDetailResponseDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let availableBadges: [String]
    let breadcrumb: [ItemSearchBreadcrumbItemDTO]
    let children: [ItemSearchChildSummaryDTO]
    let requests: [ItemSearchRequestResponseDTO]
}
