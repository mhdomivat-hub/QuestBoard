import Vapor

struct ItemSearchRequestCreateDTO: Content {
    let qty: Int?
    let averageQuality: String?
    let note: String?
}

struct ItemSearchRequestStatusUpdateDTO: Content {
    let status: ItemSearchRequestStatus
}

struct ItemSearchRequestResourcesUpdateDTO: Content {
    let hasResources: Bool
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
    let qty: Int
    let averageQuality: String?
    let note: String?
    let hasResources: Bool
    let status: ItemSearchRequestStatus
    let createdAt: Date?
    let offers: [ItemSearchOfferResponseDTO]
}

struct FulfillItemSearchRequestFromEntryDTO: Content {
    let entryId: UUID
}

struct InventoryMatchResponseDTO: Content {
    let requestId: UUID
    let itemId: UUID
    let matchedItemId: UUID
    let itemName: String
    let requesterUserId: UUID
    let requesterUsername: String
    let entryId: UUID
    let entryOwnerUserId: UUID
    let entryOwnerUsername: String
    let locationId: UUID
    let locationLabel: String
    let requestedQty: Int
    let availableQty: Int
    let averageQuality: String?
    let note: String?
    let hasEnoughQty: Bool
    let createdAt: Date?
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
struct ItemSearchOpenRequestOverviewDTO: Content {
    let requestId: UUID
    let itemId: UUID
    let itemName: String
    let itemCode: String?
    let badges: [String]
    let requesterUserId: UUID
    let requesterUsername: String
    let qty: Int
    let averageQuality: String?
    let note: String?
    let hasResources: Bool
    let hasRecipe: Bool
    let crafterCount: Int
    let totalQty: Int
    let offerCount: Int
    let createdAt: Date?
}

struct ItemSearchOpenRequestListResponseDTO: Content {
    let requests: [ItemSearchOpenRequestOverviewDTO]
}

