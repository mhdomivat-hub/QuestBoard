import Vapor

struct ItemBadgeDefinitionDTO: Content {
    let name: String
    let groupName: String?
}

struct ItemBadgeDefinitionCreateDTO: Content {
    let name: String
    let groupName: String?
}

struct ItemBadgeDefinitionUpdateDTO: Content {
    let currentName: String
    let newName: String
    let groupName: String?
}

struct ItemBadgeDefinitionDeleteDTO: Content {
    let name: String
    let groupName: String?
}

struct StorageLocationCreateDTO: Content {
    let parentId: UUID?
    let name: String
    let description: String?
}

struct StorageLocationUpdateDTO: Content {
    let parentId: UUID?
    let name: String
    let description: String?
}

struct StorageItemCreateDTO: Content {
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]?
    let hideFromBlueprints: Bool?
}

struct StorageItemUpdateDTO: Content {
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let hideFromBlueprints: Bool?
}

struct StorageItemMergeDTO: Content {
    let otherItemId: UUID
    let keepValuesFrom: String
    let parentChoice: String
}

struct StorageEntryCreateDTO: Content {
    let locationId: UUID
    let qty: Int
    let note: String?
    let userId: UUID?
}

struct StorageEntryUpdateDTO: Content {
    let qty: Int
    let note: String?
}

struct StoragePersonDTO: Content {
    let userId: UUID
    let username: String
}

struct StorageLocationFilterDTO: Content {
    let id: UUID
    let label: String
}

struct StorageLocationNodeDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let children: [StorageLocationNodeDTO]
}

struct StorageEntryResponseDTO: Content {
    let id: UUID
    let userId: UUID
    let username: String
    let locationId: UUID
    let locationLabel: String
    let qty: Int
    let note: String?
    let createdAt: Date?
}

struct StorageItemTreeNodeDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let createdAt: Date?
    let latestActivityAt: Date?
    let badges: [String]
    let hideFromBlueprints: Bool
    let crafterCount: Int
    let totalQty: Int
    let openSearchCount: Int
    let entryCount: Int
    let people: [StoragePersonDTO]
    let locations: [StorageLocationFilterDTO]
    let children: [StorageItemTreeNodeDTO]
}

struct StorageItemChildSummaryDTO: Content {
    let id: UUID
    let name: String
    let itemCode: String?
    let badges: [String]
    let hideFromBlueprints: Bool
    let crafterCount: Int
    let totalQty: Int
    let openSearchCount: Int
    let entryCount: Int
}

struct StorageBreadcrumbItemDTO: Content {
    let id: UUID
    let name: String
}

struct StorageListResponseDTO: Content {
    let items: [StorageItemTreeNodeDTO]
    let availableBadges: [String]
    let badgeDefinitions: [ItemBadgeDefinitionDTO]
    let availableUsers: [StoragePersonDTO]
    let locations: [StorageLocationNodeDTO]
    let locationFilters: [StorageLocationFilterDTO]
}

struct StorageItemDetailDTO: Content {
    let id: UUID
    let parentId: UUID?
    let name: String
    let description: String?
    let itemCode: String?
    let badges: [String]
    let availableBadges: [String]
    let badgeDefinitions: [ItemBadgeDefinitionDTO]
    let hideFromBlueprints: Bool
    let breadcrumb: [StorageBreadcrumbItemDTO]
    let children: [StorageItemChildSummaryDTO]
    let entries: [StorageEntryResponseDTO]
    let availableUsers: [StoragePersonDTO]
    let locations: [StorageLocationNodeDTO]
    let locationFilters: [StorageLocationFilterDTO]
}
