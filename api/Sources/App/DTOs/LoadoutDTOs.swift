import Vapor

struct LoadoutCreateDTO: Content {
    let name: String
    let description: String?
    let patchVersion: String
    let type: LoadoutType
}

struct LoadoutUpdateDTO: Content {
    let name: String
    let description: String?
    let patchVersion: String
    let type: LoadoutType
}

struct LoadoutItemMaterialTargetDTO: Content {
    let resourceId: UUID
    let slotName: String
    let minQuality: Int?
    let minimumQuantity: Double
}

struct LoadoutAssignedModuleReferenceDTO: Content {
    let itemId: UUID?
    let backupModuleId: UUID?
}

struct LoadoutAssignedModuleDTO: Content {
    let referenceId: String
    let sourceType: String
    let itemId: UUID?
    let backupModuleId: UUID?
    let moduleType: String?
    let name: String
    let itemCode: String?
    let badges: [String]
}

struct LoadoutItemCreateDTO: Content {
    let itemId: UUID
    let slotName: String?
    let quantity: Int?
    let sortOrder: Int?
}

struct LoadoutItemUpdateDTO: Content {
    let slotName: String?
    let quantity: Int
    let sortOrder: Int?
    let materialTargets: [LoadoutItemMaterialTargetDTO]?
    let moduleAssignments: [LoadoutAssignedModuleReferenceDTO]?
}

struct LoadoutRequiredResourceDTO: Content {
    let resourceId: UUID
    let resourceName: String
    let badges: [String]
    let quantity: Double
    let minimumStoredQuantity: Double
    let effectiveRequiredQuantity: Double
    let minQuality: Int?
    let totalStoredQty: Int
    let missingQty: Double
    let missingForViability: Double
}

struct LoadoutItemRecipeResourceDTO: Content {
    let resourceId: UUID
    let resourceName: String
    let badges: [String]
    let slotName: String
    let quantity: Double
    let minQuality: Int?
    let minimumStoredQuantity: Double
}

struct LoadoutItemResponseDTO: Content {
    let id: UUID
    let itemId: UUID
    let itemName: String
    let itemCode: String?
    let badges: [String]
    let slotName: String?
    let quantity: Int
    let sortOrder: Int
    let moduleSupportType: String?
    let assignedModules: [LoadoutAssignedModuleDTO]
    let recipeResources: [LoadoutItemRecipeResourceDTO]
}

struct LoadoutSummaryDTO: Content {
    let id: UUID
    let name: String
    let description: String?
    let patchVersion: String
    let type: LoadoutType
    let itemCount: Int
    let materialCount: Int
    let createdAt: Date?
    let updatedAt: Date?
}

struct LoadoutDetailDTO: Content {
    let id: UUID
    let name: String
    let description: String?
    let patchVersion: String
    let type: LoadoutType
    let items: [LoadoutItemResponseDTO]
    let requiredResources: [LoadoutRequiredResourceDTO]
    let createdAt: Date?
    let updatedAt: Date?
}

struct LoadoutListResponseDTO: Content {
    let loadouts: [LoadoutSummaryDTO]
}

