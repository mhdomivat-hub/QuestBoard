import Vapor
import Fluent

private func requireLoadoutUser(_ req: Request) throws -> User {
    let user = try requireAuthenticatedUser(req)
    if user.role == .guest {
        throw Abort(.forbidden, reason: "Guests may not manage loadouts")
    }
    return user
}

private func sanitizeLoadoutName(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw Abort(.badRequest, reason: "Loadout name required")
    }
    return String(trimmed.prefix(120))
}

private func sanitizeLoadoutDescription(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : String(trimmed.prefix(1000))
}

private func sanitizeLoadoutPatchVersion(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw Abort(.badRequest, reason: "Patch version required")
    }
    return String(trimmed.prefix(64))
}

private func sanitizeLoadoutSlotName(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
}

private func sanitizeMinimumMaterialQuantity(_ raw: Double) throws -> Double {
    guard raw >= 0 else {
        throw Abort(.badRequest, reason: "Minimum quantity must be >= 0")
    }
    return raw
}

private func decodeLoadoutBadges(_ raw: String?) -> [String] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func loadoutMineableBadges(_ raw: String?) -> [String] {
    let allowed = Set(["Handminable", "Shipminable"])
    return decodeLoadoutBadges(raw).filter { allowed.contains($0) }
}

private let defaultLoadoutMaterialMinQuality = 500

private func normalizedLoadoutMaterialMinQuality(_ raw: Int?) -> Int {
    raw ?? defaultLoadoutMaterialMinQuality
}

private func normalizedStoredLoadoutMaterialMinQuality(_ raw: Int) -> Int {
    raw >= 0 ? raw : defaultLoadoutMaterialMinQuality
}

private func loadoutMaterialTargetKey(resourceId: UUID, slotName: String, minQuality: Int?) -> String {
    let normalizedSlotName = slotName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return "\(resourceId.uuidString.lowercased())::\(normalizedSlotName)::\(normalizedLoadoutMaterialMinQuality(minQuality))"
}

private func isMiningLaserItem(_ item: Blueprint) -> Bool {
    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let itemCode = (item.itemCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let badgeSet = Set(decodeLoadoutBadges(item.badgesCSV).map { $0.lowercased() })
    return name.contains("mining laser") || itemCode.contains("mining_laser") || itemCode.contains("weaponmining") || badgeSet.contains("mining laser")
}

private func isFPSWeaponItem(_ item: Blueprint) -> Bool {
    let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let itemCode = (item.itemCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let badgeSet = Set(decodeLoadoutBadges(item.badgesCSV).map { $0.lowercased() })

    let weaponKeywords = ["pistol", "rifle", "smg", "sniper", "shotgun", "lmg", "weapon", "launcher"]
    let hasWeaponKeyword = weaponKeywords.contains { keyword in
        name.contains(keyword) || itemCode.contains(keyword)
    }

    return hasWeaponKeyword || badgeSet.contains("waffe") || badgeSet.contains("weapon") || badgeSet.contains("fps")
}

private func loadoutModuleSupportType(for item: Blueprint) -> LoadoutBackupModuleType? {
    if isMiningLaserItem(item) {
        return .miningLaser
    }
    if isFPSWeaponItem(item) {
        return .fpsWeapon
    }
    return nil
}

private func uniqueOrderedUUIDs(_ values: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    return values.filter { seen.insert($0).inserted }
}

private func loadoutModuleReferenceId(itemId: UUID?, backupModuleId: UUID?) -> String {
    if let itemId {
        return "item:\(itemId.uuidString.lowercased())"
    }
    if let backupModuleId {
        return "backup:\(backupModuleId.uuidString.lowercased())"
    }
    return "unknown"
}

private func normalizedModuleReferences(_ values: [LoadoutAssignedModuleReferenceDTO]) throws -> [LoadoutAssignedModuleReferenceDTO] {
    try values.map { value in
        let itemId = value.itemId
        let backupModuleId = value.backupModuleId
        guard (itemId != nil) != (backupModuleId != nil) else {
            throw Abort(.badRequest, reason: "Each module assignment must reference exactly one source")
        }
        return value
    }
}

private struct AggregatedLoadoutResource {
    let resourceId: UUID
    let resourceName: String
    let badges: [String]
    let minQuality: Int?
    var quantity: Double
    var minimumStoredQuantity: Double
    var totalStoredQty: Int
}

private func buildLoadoutDetail(
    loadout: Loadout,
    assignments: [LoadoutItem],
    itemsById: [UUID: Blueprint],
    backupModulesById: [UUID: MiningModuleBackupDefinition],
    recipeResources: [BlueprintRecipeResource],
    entriesByItemId: [UUID: [StorageEntry]],
    materialTargets: [LoadoutItemMaterialTarget],
    moduleAssignments: [LoadoutItemModuleAssignment]
) throws -> LoadoutDetailDTO {
    let recipesByBlueprintId = Dictionary(grouping: recipeResources, by: { $0.$blueprint.id })
    let targetsByLoadoutItemId = Dictionary(grouping: materialTargets, by: { $0.$loadoutItem.id }).mapValues { targets in
        Dictionary(uniqueKeysWithValues: targets.map { target in
            (
                loadoutMaterialTargetKey(
                    resourceId: target.$resource.id,
                    slotName: target.slotName,
                    minQuality: normalizedStoredLoadoutMaterialMinQuality(target.minQualityKey)
                ),
                target
            )
        })
    }
    let modulesByLoadoutItemId = Dictionary(grouping: moduleAssignments, by: { $0.$loadoutItem.id })
    var aggregatedByKey: [String: AggregatedLoadoutResource] = [:]

    let itemDTOs = try assignments
        .sorted {
            if $0.sortOrder == $1.sortOrder {
                return ($0.slotName ?? "").localizedCaseInsensitiveCompare($1.slotName ?? "") == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
        .map { assignment -> LoadoutItemResponseDTO in
            let assignmentId = try assignment.requireID()
            let itemId = assignment.$item.id
            guard let item = itemsById[itemId] else {
                throw Abort(.internalServerError, reason: "Loadout item missing")
            }
            let itemTargets = targetsByLoadoutItemId[assignmentId] ?? [:]
            let itemRecipes = (recipesByBlueprintId[itemId] ?? []).sorted {
                if $0.slotName == $1.slotName {
                    return $0.resourceName.localizedCaseInsensitiveCompare($1.resourceName) == .orderedAscending
                }
                return $0.slotName.localizedCaseInsensitiveCompare($1.slotName) == .orderedAscending
            }
            let assignedModules = (modulesByLoadoutItemId[assignmentId] ?? [])
                .sorted { left, right in
                    if left.sortOrder == right.sortOrder {
                        let leftName = itemsById[left.$moduleItem.id ?? UUID()]?.name ?? backupModulesById[left.$backupModule.id ?? UUID()]?.name ?? ""
                        let rightName = itemsById[right.$moduleItem.id ?? UUID()]?.name ?? backupModulesById[right.$backupModule.id ?? UUID()]?.name ?? ""
                        return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
                    }
                    return left.sortOrder < right.sortOrder
                }
                .compactMap { moduleAssignment -> LoadoutAssignedModuleDTO? in
                    if let moduleItemId = moduleAssignment.$moduleItem.id,
                       let moduleItem = itemsById[moduleItemId] {
                        return LoadoutAssignedModuleDTO(
                            referenceId: loadoutModuleReferenceId(itemId: moduleItemId, backupModuleId: nil),
                            sourceType: "item",
                            itemId: moduleItemId,
                            backupModuleId: nil,
                            moduleType: loadoutModuleSupportType(for: moduleItem)?.rawValue,
                            name: moduleItem.name,
                            itemCode: moduleItem.itemCode,
                            badges: decodeLoadoutBadges(moduleItem.badgesCSV)
                        )
                    }
                    if let backupModuleId = moduleAssignment.$backupModule.id,
                       let backupModule = backupModulesById[backupModuleId] {
                        return LoadoutAssignedModuleDTO(
                            referenceId: loadoutModuleReferenceId(itemId: nil, backupModuleId: backupModuleId),
                            sourceType: "backup",
                            itemId: nil,
                            backupModuleId: backupModuleId,
                            moduleType: backupModule.moduleType.rawValue,
                            name: backupModule.name,
                            itemCode: nil,
                            badges: []
                        )
                    }
                    return nil
                }

            let recipeDTOs = itemRecipes.map { recipe -> LoadoutItemRecipeResourceDTO in
                let resourceId = recipe.$resource.id
                let resourceBadges = loadoutMineableBadges(itemsById[resourceId]?.badgesCSV)
                let totalStoredQty = (entriesByItemId[resourceId] ?? []).reduce(0) { $0 + $1.qty }
                let normalizedMinQuality = normalizedLoadoutMaterialMinQuality(recipe.minQuality)
                let targetKey = loadoutMaterialTargetKey(resourceId: resourceId, slotName: recipe.slotName, minQuality: recipe.minQuality)
                let storedOverrideMinQuality = itemTargets[targetKey]?.minimumQuantity ?? 0
                let effectiveMinQuality = max(normalizedMinQuality, Int(storedOverrideMinQuality.rounded(.down)))
                let aggregateKey = "\(resourceId.uuidString.lowercased())::\(effectiveMinQuality)"
                let requiredQuantity = recipe.quantity * Double(assignment.quantity)
                var current = aggregatedByKey[aggregateKey] ?? AggregatedLoadoutResource(
                    resourceId: resourceId,
                    resourceName: recipe.resourceName,
                    badges: resourceBadges,
                    minQuality: effectiveMinQuality,
                    quantity: 0,
                    minimumStoredQuantity: 0,
                    totalStoredQty: totalStoredQty
                )
                current.quantity += requiredQuantity
                current.totalStoredQty = totalStoredQty
                aggregatedByKey[aggregateKey] = current

                return LoadoutItemRecipeResourceDTO(
                    resourceId: resourceId,
                    resourceName: recipe.resourceName,
                    badges: resourceBadges,
                    slotName: recipe.slotName,
                    quantity: recipe.quantity,
                    minQuality: effectiveMinQuality,
                    minimumStoredQuantity: Double(effectiveMinQuality)
                )
            }

            return LoadoutItemResponseDTO(
                id: assignmentId,
                itemId: itemId,
                itemName: item.name,
                itemCode: item.itemCode,
                badges: decodeLoadoutBadges(item.badgesCSV),
                slotName: assignment.slotName,
                quantity: assignment.quantity,
                sortOrder: assignment.sortOrder,
                moduleSupportType: loadoutModuleSupportType(for: item)?.rawValue,
                assignedModules: assignedModules,
                recipeResources: recipeDTOs
            )
        }

    let requiredResources = aggregatedByKey.values
        .sorted { left, right in
            if left.resourceName == right.resourceName {
                return (left.minQuality ?? -1) < (right.minQuality ?? -1)
            }
            return left.resourceName.localizedCaseInsensitiveCompare(right.resourceName) == .orderedAscending
        }
        .map { resource in
            let effectiveRequiredQuantity = max(resource.quantity, resource.minimumStoredQuantity)
            return LoadoutRequiredResourceDTO(
                resourceId: resource.resourceId,
                resourceName: resource.resourceName,
                badges: resource.badges,
                quantity: resource.quantity,
                minimumStoredQuantity: resource.minimumStoredQuantity,
                effectiveRequiredQuantity: effectiveRequiredQuantity,
                minQuality: resource.minQuality,
                totalStoredQty: resource.totalStoredQty,
                missingQty: max(0, resource.quantity - Double(resource.totalStoredQty)),
                missingForViability: max(0, effectiveRequiredQuantity - Double(resource.totalStoredQty))
            )
        }

    return LoadoutDetailDTO(
        id: try loadout.requireID(),
        name: loadout.name,
        description: loadout.description,
        patchVersion: loadout.patchVersion,
        type: loadout.type,
        items: itemDTOs,
        requiredResources: requiredResources,
        createdAt: loadout.createdAt,
        updatedAt: loadout.updatedAt
    )
}

private func getLoadoutDetailById(_ loadoutId: UUID, on db: Database) async throws -> LoadoutDetailDTO {
    guard let loadout = try await Loadout.find(loadoutId, on: db) else {
        throw Abort(.notFound)
    }

    let assignments = try await LoadoutItem.query(on: db)
        .filter(\.$loadout.$id == loadoutId)
        .all()
    let items = try await Blueprint.query(on: db)
        .filter(\.$category == .blueprints)
        .all()
    let miningModuleBackups = try await MiningModuleBackupDefinition.query(on: db).all()
    let recipeResources = try await BlueprintRecipeResource.query(on: db).all()
    let storageEntries = try await StorageEntry.query(on: db).all()
    let assignmentIds = Array(Set(assignments.compactMap { $0.id }))
    let materialTargets = assignmentIds.isEmpty ? [] : try await LoadoutItemMaterialTarget.query(on: db)
        .filter(\.$loadoutItem.$id ~~ assignmentIds)
        .all()
    let moduleAssignments = assignmentIds.isEmpty ? [] : try await LoadoutItemModuleAssignment.query(on: db)
        .filter(\.$loadoutItem.$id ~~ assignmentIds)
        .all()

    let itemsById = Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.id.map { ($0, item) }
    })
    let backupModulesById = Dictionary(uniqueKeysWithValues: miningModuleBackups.compactMap { module in
        module.id.map { ($0, module) }
    })
    let entriesByItemId = Dictionary(grouping: storageEntries, by: { $0.$item.id })

    return try buildLoadoutDetail(
        loadout: loadout,
        assignments: assignments,
        itemsById: itemsById,
        backupModulesById: backupModulesById,
        recipeResources: recipeResources,
        entriesByItemId: entriesByItemId,
        materialTargets: materialTargets,
        moduleAssignments: moduleAssignments
    )
}

func listLoadouts(_ req: Request) async throws -> LoadoutListResponseDTO {
    _ = try requireLoadoutUser(req)

    let loadouts = try await Loadout.query(on: req.db)
        .sort(\.$updatedAt, .descending)
        .all()
    let assignments = try await LoadoutItem.query(on: req.db).all()
    let recipeResources = try await BlueprintRecipeResource.query(on: req.db).all()

    let assignmentsByLoadoutId = Dictionary(grouping: assignments, by: { $0.$loadout.id })
    let recipeCountsByItemId = Dictionary(grouping: recipeResources, by: { $0.$blueprint.id }).mapValues { $0.count }

    return LoadoutListResponseDTO(
        loadouts: try loadouts.map { loadout in
            let loadoutId = try loadout.requireID()
            let loadoutAssignments = assignmentsByLoadoutId[loadoutId] ?? []
            let materialCount = loadoutAssignments.reduce(0) { partial, assignment in
                partial + (recipeCountsByItemId[assignment.$item.id] ?? 0)
            }
            return LoadoutSummaryDTO(
                id: loadoutId,
                name: loadout.name,
                description: loadout.description,
                patchVersion: loadout.patchVersion,
                type: loadout.type,
                itemCount: loadoutAssignments.count,
                materialCount: materialCount,
                createdAt: loadout.createdAt,
                updatedAt: loadout.updatedAt
            )
        }
    )
}

func getLoadout(_ req: Request) async throws -> LoadoutDetailDTO {
    _ = try requireLoadoutUser(req)
    guard let loadoutId = req.parameters.get("loadoutID", as: UUID.self) else {
        throw Abort(.badRequest)
    }
    return try await getLoadoutDetailById(loadoutId, on: req.db)
}

func createLoadout(_ req: Request) async throws -> LoadoutDetailDTO {
    let actor = try requireLoadoutUser(req)
    let body = try req.content.decode(LoadoutCreateDTO.self)

    let loadout = Loadout(
        name: try sanitizeLoadoutName(body.name),
        description: sanitizeLoadoutDescription(body.description),
        patchVersion: try sanitizeLoadoutPatchVersion(body.patchVersion),
        type: body.type
    )
    try await loadout.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "loadout.create", entityType: "loadout", entityId: loadout.id)
    return try await getLoadoutDetailById(try loadout.requireID(), on: req.db)
}

func updateLoadout(_ req: Request) async throws -> LoadoutDetailDTO {
    let actor = try requireLoadoutUser(req)
    guard let loadoutId = req.parameters.get("loadoutID", as: UUID.self),
          let loadout = try await Loadout.find(loadoutId, on: req.db) else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(LoadoutUpdateDTO.self)
    loadout.name = try sanitizeLoadoutName(body.name)
    loadout.description = sanitizeLoadoutDescription(body.description)
    loadout.patchVersion = try sanitizeLoadoutPatchVersion(body.patchVersion)
    loadout.type = body.type
    try await loadout.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "loadout.update", entityType: "loadout", entityId: loadoutId)
    return try await getLoadoutDetailById(loadoutId, on: req.db)
}

func deleteLoadout(_ req: Request) async throws -> HTTPStatus {
    let actor = try requireLoadoutUser(req)
    guard let loadoutId = req.parameters.get("loadoutID", as: UUID.self),
          let loadout = try await Loadout.find(loadoutId, on: req.db) else {
        throw Abort(.notFound)
    }

    try await loadout.delete(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "loadout.delete", entityType: "loadout", entityId: loadoutId)
    return .noContent
}

func addLoadoutItem(_ req: Request) async throws -> LoadoutDetailDTO {
    let actor = try requireLoadoutUser(req)
    guard let loadoutId = req.parameters.get("loadoutID", as: UUID.self),
          try await Loadout.find(loadoutId, on: req.db) != nil else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(LoadoutItemCreateDTO.self)
    guard body.quantity ?? 1 > 0 else {
        throw Abort(.badRequest, reason: "Quantity must be > 0")
    }
    guard try await Blueprint.find(body.itemId, on: req.db) != nil else {
        throw Abort(.badRequest, reason: "Item not found")
    }

    let assignment = LoadoutItem(
        loadoutID: loadoutId,
        itemID: body.itemId,
        slotName: sanitizeLoadoutSlotName(body.slotName),
        quantity: body.quantity ?? 1,
        sortOrder: body.sortOrder ?? 0
    )
    try await assignment.save(on: req.db)
    let assignmentId = try assignment.requireID()
    let recipeResources = try await BlueprintRecipeResource.query(on: req.db)
        .filter(\.$blueprint.$id == body.itemId)
        .all()

    for recipe in recipeResources {
        let defaultTarget = LoadoutItemMaterialTarget(
            loadoutItemID: assignmentId,
            resourceID: recipe.$resource.id,
            slotName: String(recipe.slotName.prefix(120)),
            minQualityKey: normalizedLoadoutMaterialMinQuality(recipe.minQuality),
            minimumQuantity: Double(defaultLoadoutMaterialMinQuality)
        )
        try await defaultTarget.save(on: req.db)
    }


    await recordAuditEvent(on: req, actor: actor, action: "loadout.item.create", entityType: "loadout", entityId: loadoutId, details: "itemId=\(body.itemId)")
    return try await getLoadoutDetailById(loadoutId, on: req.db)
}

func updateLoadoutItem(_ req: Request) async throws -> LoadoutDetailDTO {
    let actor = try requireLoadoutUser(req)
    guard let loadoutId = req.parameters.get("loadoutID", as: UUID.self),
          let loadoutItemId = req.parameters.get("loadoutItemID", as: UUID.self),
          let assignment = try await LoadoutItem.find(loadoutItemId, on: req.db) else {
        throw Abort(.notFound)
    }
    guard assignment.$loadout.id == loadoutId else {
        throw Abort(.badRequest)
    }

    let body = try req.content.decode(LoadoutItemUpdateDTO.self)
    guard body.quantity > 0 else {
        throw Abort(.badRequest, reason: "Quantity must be > 0")
    }

    assignment.slotName = sanitizeLoadoutSlotName(body.slotName)
    assignment.quantity = body.quantity
    if let sortOrder = body.sortOrder {
        assignment.sortOrder = sortOrder
    }
    try await assignment.save(on: req.db)

    guard let loadoutItemBlueprint = try await Blueprint.find(assignment.$item.id, on: req.db) else {
        throw Abort(.internalServerError, reason: "Loadout item missing")
    }

    if let materialTargets = body.materialTargets {
        let validRecipeResources = try await BlueprintRecipeResource.query(on: req.db)
            .filter(\.$blueprint.$id == assignment.$item.id)
            .all()
        let validKeys = Set(validRecipeResources.map { recipe in
            loadoutMaterialTargetKey(resourceId: recipe.$resource.id, slotName: recipe.slotName, minQuality: recipe.minQuality)
        })

        try await LoadoutItemMaterialTarget.query(on: req.db)
            .filter(\.$loadoutItem.$id == loadoutItemId)
            .delete()

        for target in materialTargets {
            let minimumQuantity = try sanitizeMinimumMaterialQuantity(target.minimumQuantity)
            guard minimumQuantity > 0 else {
                continue
            }
            let key = loadoutMaterialTargetKey(resourceId: target.resourceId, slotName: target.slotName, minQuality: target.minQuality)
            guard validKeys.contains(key) else {
                throw Abort(.badRequest, reason: "Invalid material target for loadout item")
            }
            let storedTarget = LoadoutItemMaterialTarget(
                loadoutItemID: loadoutItemId,
                resourceID: target.resourceId,
                slotName: String(target.slotName.prefix(120)),
                minQualityKey: normalizedLoadoutMaterialMinQuality(target.minQuality),
                minimumQuantity: minimumQuantity
            )
            try await storedTarget.save(on: req.db)
        }
    }

    if let moduleAssignments = body.moduleAssignments {
        let orderedModuleAssignments = try normalizedModuleReferences(moduleAssignments)
        let supportedModuleType = loadoutModuleSupportType(for: loadoutItemBlueprint)

        if supportedModuleType == nil && !orderedModuleAssignments.isEmpty {
            throw Abort(.badRequest, reason: "Modules are only supported for mining lasers and FPS weapons")
        }

        let orderedItemIds = uniqueOrderedUUIDs(orderedModuleAssignments.compactMap(\.itemId))
        let orderedBackupIds = uniqueOrderedUUIDs(orderedModuleAssignments.compactMap(\.backupModuleId))

        if orderedItemIds.contains(assignment.$item.id) {
            throw Abort(.badRequest, reason: "An item may not assign itself as module")
        }

        let moduleItems = try await Blueprint.query(on: req.db)
            .filter(\.$category == .blueprints)
            .filter(\.$id ~~ orderedItemIds)
            .all()
        let validModuleIds = Set(moduleItems.compactMap(\.id))
        guard validModuleIds.count == orderedItemIds.count else {
            throw Abort(.badRequest, reason: "Invalid module item")
        }

        if let supportedModuleType {
            let invalidModuleItem = moduleItems.first { loadoutModuleSupportType(for: $0) != supportedModuleType }
            if invalidModuleItem != nil {
                throw Abort(.badRequest, reason: "Module item type does not match loadout item")
            }
        }

        let backupModules = try await MiningModuleBackupDefinition.query(on: req.db)
            .filter(\.$id ~~ orderedBackupIds)
            .all()
        let validBackupIds = Set(backupModules.compactMap(\.id))
        guard validBackupIds.count == orderedBackupIds.count else {
            throw Abort(.badRequest, reason: "Invalid backup module")
        }

        if let supportedModuleType {
            let invalidBackupModule = backupModules.first { $0.moduleType != supportedModuleType }
            if invalidBackupModule != nil {
                throw Abort(.badRequest, reason: "Backup module type does not match loadout item")
            }
        }

        try await LoadoutItemModuleAssignment.query(on: req.db)
            .filter(\.$loadoutItem.$id == loadoutItemId)
            .delete()

        for (index, moduleReference) in orderedModuleAssignments.enumerated() {
            let storedAssignment = LoadoutItemModuleAssignment(
                loadoutItemID: loadoutItemId,
                moduleItemID: moduleReference.itemId,
                backupModuleID: moduleReference.backupModuleId,
                sortOrder: index
            )
            try await storedAssignment.save(on: req.db)
        }
    }

    await recordAuditEvent(on: req, actor: actor, action: "loadout.item.update", entityType: "loadout", entityId: loadoutId, details: "loadoutItemId=\(loadoutItemId)")
    return try await getLoadoutDetailById(loadoutId, on: req.db)
}

func deleteLoadoutItem(_ req: Request) async throws -> LoadoutDetailDTO {
    let actor = try requireLoadoutUser(req)
    guard let loadoutId = req.parameters.get("loadoutID", as: UUID.self),
          let loadoutItemId = req.parameters.get("loadoutItemID", as: UUID.self),
          let assignment = try await LoadoutItem.find(loadoutItemId, on: req.db) else {
        throw Abort(.notFound)
    }
    guard assignment.$loadout.id == loadoutId else {
        throw Abort(.badRequest)
    }

    try await assignment.delete(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "loadout.item.delete", entityType: "loadout", entityId: loadoutId, details: "loadoutItemId=\(loadoutItemId)")
    return try await getLoadoutDetailById(loadoutId, on: req.db)
}





