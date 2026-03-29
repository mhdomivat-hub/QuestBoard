import Vapor
import Fluent

private func requireStorageEditor(_ req: Request) throws -> User {
    let user = try requireNonGuestUser(req)
    return user
}

private func requireStorageAdmin(_ user: User) throws {
    guard user.role == .admin || user.role == .superAdmin else {
        throw Abort(.forbidden, reason: "Only admins may manage storage structure")
    }
}

private func canAdminChangeBlueprintVisibility(_ user: User) -> Bool {
    user.role == .admin || user.role == .superAdmin
}

private func requireItemBadgeAdmin(_ user: User) throws {
    guard user.role == .admin || user.role == .superAdmin else {
        throw Abort(.forbidden, reason: "Only admins may manage badges")
    }
}

private func sanitizeStorageName(_ raw: String) throws -> String {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
        throw Abort(.badRequest, reason: "Name required")
    }
    return String(value.prefix(120))
}

private func sanitizeStorageDescription(_ raw: String?) -> String? {
    let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : String(value.prefix(1000))
}

private func sanitizeStorageItemCode(_ raw: String?) -> String? {
    let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? nil : String(value.prefix(160))
}

private func sanitizeStorageHideFromBlueprints(_ raw: Bool?) -> Bool {
    raw ?? false
}

private func sanitizeStorageBadges(_ values: [String]?) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for raw in values ?? [] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let normalized = String(trimmed.prefix(32))
        let key = normalized.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(normalized)
        if result.count >= 8 { break }
    }
    return result
}

private func sanitizeItemBadgeName(_ raw: String) throws -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw Abort(.badRequest, reason: "Badge name required")
    }
    return String(trimmed.prefix(32))
}

private func sanitizeItemBadgeGroupName(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(40))
}

private func badgeGroupMatches(_ definition: ItemBadgeDefinition, groupName: String?) -> Bool {
    let normalizedLeft = definition.groupName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let normalizedRight = groupName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return normalizedLeft == normalizedRight
}

private func encodeStorageBadges(_ badges: [String]) -> String? {
    guard !badges.isEmpty else { return nil }
    return badges.joined(separator: ",")
}

private func decodeStorageBadges(_ raw: String?) -> [String] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

private func collectItemDescendantIds(rootId: UUID, groupedByParent: [UUID?: [Blueprint]]) -> Set<UUID> {
    var result: Set<UUID> = []
    var stack: [UUID] = [rootId]
    while let current = stack.popLast() {
        for child in groupedByParent[current] ?? [] {
            guard let childId = child.id, !result.contains(childId) else { continue }
            result.insert(childId)
            stack.append(childId)
        }
    }
    return result
}

private func collectLocationDescendantIds(rootId: UUID, groupedByParent: [UUID?: [StorageLocation]]) -> Set<UUID> {
    var result: Set<UUID> = []
    var stack: [UUID] = [rootId]
    while let current = stack.popLast() {
        for child in groupedByParent[current] ?? [] {
            guard let childId = child.id, !result.contains(childId) else { continue }
            result.insert(childId)
            stack.append(childId)
        }
    }
    return result
}

private func buildLocationLabel(locationId: UUID, byId: [UUID: StorageLocation]) -> String {
    var names: [String] = []
    var currentId: UUID? = locationId
    while let id = currentId, let location = byId[id] {
        names.insert(location.name, at: 0)
        currentId = location.$parent.id
    }
    return names.joined(separator: " > ")
}

private func buildLocationTree(parentId: UUID?, grouped: [UUID?: [StorageLocation]]) throws -> [StorageLocationNodeDTO] {
    let nodes = (grouped[parentId] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return try nodes.map { node in
        guard let id = node.id else { throw Abort(.internalServerError) }
        return .init(
            id: id,
            parentId: node.$parent.id,
            name: node.name,
            description: node.description,
            children: try buildLocationTree(parentId: id, grouped: grouped)
        )
    }
}

private func locationFilters(from locations: [StorageLocation]) -> [StorageLocationFilterDTO] {
    let byId = Dictionary(uniqueKeysWithValues: locations.compactMap { location in
        location.id.map { ($0, location) }
    })
    return locations.compactMap { location in
        guard let id = location.id else { return nil }
        return .init(id: id, label: buildLocationLabel(locationId: id, byId: byId))
    }.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
}

private func availablePeople(from users: [User]) -> [StoragePersonDTO] {
    users.compactMap { user in
        guard let id = user.id else { return nil }
        return .init(userId: id, username: user.username)
    }.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
}

private func entryDTOs(entries: [StorageEntry], usersById: [UUID: User], locationsById: [UUID: StorageLocation]) -> [StorageEntryResponseDTO] {
    entries.compactMap { entry in
        guard let entryId = entry.id,
              let user = usersById[entry.$user.id], let userId = user.id,
              locationsById[entry.$location.id] != nil else {
            return nil
        }
        return .init(
            id: entryId,
            userId: userId,
            username: user.username,
            locationId: entry.$location.id,
            locationLabel: buildLocationLabel(locationId: entry.$location.id, byId: locationsById),
            qty: entry.qty,
            note: entry.note,
            createdAt: entry.createdAt
        )
    }.sorted { a, b in
        let left = a.createdAt?.timeIntervalSince1970 ?? 0
        let right = b.createdAt?.timeIntervalSince1970 ?? 0
        return left > right
    }
}

private func collectBadges(items: [Blueprint]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for badge in items.flatMap({ decodeStorageBadges($0.badgesCSV) }) {
        let key = badge.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(badge)
    }
    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func buildBadgeDefinitions(
    items: [Blueprint],
    definitions: [ItemBadgeDefinition]
) -> [ItemBadgeDefinitionDTO] {
    var groupedByName: [String: ItemBadgeDefinitionDTO] = [:]

    for definition in definitions {
        let key = definition.name.lowercased()
        groupedByName[key] = .init(name: definition.name, groupName: definition.groupName)
    }

    for badge in collectBadges(items: items) {
        let key = badge.lowercased()
        if groupedByName[key] == nil {
            groupedByName[key] = .init(name: badge, groupName: nil)
        }
    }

    return groupedByName.values.sorted { lhs, rhs in
        let leftGroup = lhs.groupName ?? ""
        let rightGroup = rhs.groupName ?? ""
        if leftGroup.caseInsensitiveCompare(rightGroup) != .orderedSame {
            return leftGroup.localizedCaseInsensitiveCompare(rightGroup) == .orderedAscending
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private func availableBadgeNames(from definitions: [ItemBadgeDefinitionDTO]) -> [String] {
    definitions.map(\.name)
}

private func ensureBadgeDefinitionsExist(
    badges: [String],
    actor: User,
    on database: Database
) async throws {
    guard !badges.isEmpty else { return }

    let existing = try await ItemBadgeDefinition.query(on: database).all()
    var existingByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.name.lowercased(), $0) })

    for badge in badges {
        let key = badge.lowercased()
        if existingByKey[key] != nil {
            continue
        }
        try requireItemBadgeAdmin(actor)
        let definition = ItemBadgeDefinition(name: badge, groupName: nil)
        try await definition.save(on: database)
        existingByKey[key] = definition
    }
}

private func buildStorageActivityMap(
    items: [Blueprint],
    entries: [StorageEntry]
) -> [UUID: Date] {
    var result: [UUID: Date] = [:]

    func register(_ date: Date?, for itemId: UUID) {
        guard let date else { return }
        if let existing = result[itemId], existing >= date {
            return
        }
        result[itemId] = date
    }

    for item in items {
        guard let itemId = item.id else { continue }
        register(item.createdAt, for: itemId)
        register(item.updatedAt, for: itemId)
    }

    for entry in entries {
        register(entry.createdAt, for: entry.$item.id)
    }

    return result
}

private func buildItemTree(
    parentId: UUID?,
    grouped: [UUID?: [Blueprint]],
    entriesByItem: [UUID: [StorageEntryResponseDTO]],
    latestActivityMap: [UUID: Date],
    crafterCountsByItem: [UUID: Int],
    openSearchCountsByItem: [UUID: Int],
    craftedByActorItemIds: Set<UUID>
) throws -> [StorageItemTreeNodeDTO] {
    let nodes = (grouped[parentId] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return try nodes.map { node in
        guard let id = node.id else { throw Abort(.internalServerError) }
        let children = try buildItemTree(
            parentId: id,
            grouped: grouped,
            entriesByItem: entriesByItem,
            latestActivityMap: latestActivityMap,
            crafterCountsByItem: crafterCountsByItem,
            openSearchCountsByItem: openSearchCountsByItem,
            craftedByActorItemIds: craftedByActorItemIds
        )
        let ownEntries = entriesByItem[id] ?? []
        let ownQty = ownEntries.reduce(0) { $0 + $1.qty }
        let childQty = children.reduce(0) { $0 + $1.totalQty }
        let ownCrafterCount = crafterCountsByItem[id] ?? 0
        let ownOpenSearchCount = openSearchCountsByItem[id] ?? 0
        let childOpenSearchCount = children.reduce(0) { $0 + $1.openSearchCount }
        let people = Dictionary(grouping: ownEntries, by: { $0.userId }).compactMap { _, values in
            values.first.map { StoragePersonDTO(userId: $0.userId, username: $0.username) }
        }.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        let locations = Dictionary(grouping: ownEntries, by: { $0.locationId }).compactMap { _, values in
            values.first.map { StorageLocationFilterDTO(id: $0.locationId, label: $0.locationLabel) }
        }.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

        return .init(
            id: id,
            parentId: node.$parent.id,
            name: node.name,
            description: node.description,
            itemCode: node.itemCode,
            createdAt: node.createdAt,
            latestActivityAt: latestActivityMap[id],
            badges: decodeStorageBadges(node.badgesCSV),
            hideFromBlueprints: node.hideFromBlueprints,
            craftedByMe: craftedByActorItemIds.contains(id),
            crafterCount: ownCrafterCount,
            totalQty: ownQty + childQty,
            openSearchCount: ownOpenSearchCount + childOpenSearchCount,
            entryCount: ownEntries.count,
            people: people,
            locations: locations,
            children: children
        )
    }
}

private func storageItemDetail(
    item: Blueprint,
    allItems: [Blueprint],
    badgeDefinitions: [ItemBadgeDefinition],
    locations: [StorageLocation],
    users: [User],
    entries: [StorageEntry],
    crafterCountsByItem: [UUID: Int],
    openSearchCountsByItem: [UUID: Int]
) throws -> StorageItemDetailDTO {
    guard let itemId = item.id else { throw Abort(.internalServerError) }
    let badgeDefinitionsDTO = buildBadgeDefinitions(items: allItems, definitions: badgeDefinitions)
    let itemsById = Dictionary(uniqueKeysWithValues: allItems.compactMap { entry in
        entry.id.map { ($0, entry) }
    })
    let locationsById = Dictionary(uniqueKeysWithValues: locations.compactMap { entry in
        entry.id.map { ($0, entry) }
    })
    let usersById = Dictionary(uniqueKeysWithValues: users.compactMap { entry in
        entry.id.map { ($0, entry) }
    })
    let groupedItems = Dictionary(grouping: allItems, by: { $0.$parent.id })
    let groupedLocations = Dictionary(grouping: locations, by: { $0.$parent.id })

    var breadcrumbIds: [UUID] = []
    var currentParent = item.$parent.id
    while let parentId = currentParent, let parent = itemsById[parentId] {
        breadcrumbIds.insert(parentId, at: 0)
        currentParent = parent.$parent.id
    }

    let breadcrumb = breadcrumbIds.compactMap { id in
        itemsById[id].map { StorageBreadcrumbItemDTO(id: id, name: $0.name) }
    } + [StorageBreadcrumbItemDTO(id: itemId, name: item.name)]

    let entryDtos = entryDTOs(entries: entries.filter { $0.$item.id == itemId }, usersById: usersById, locationsById: locationsById)
    let entriesByItemId = Dictionary(grouping: entries, by: { $0.$item.id })

    func buildChildSummaries(parentId: UUID) throws -> [StorageItemChildSummaryDTO] {
        let children = (groupedItems[parentId] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return try children.map { child in
            guard let childId = child.id else { throw Abort(.internalServerError) }
            let nestedChildren = try buildChildSummaries(parentId: childId)
            let ownEntries = entriesByItemId[childId] ?? []
            let ownQty = ownEntries.reduce(0) { $0 + $1.qty }
            let ownEntryCount = ownEntries.count

            return .init(
                id: childId,
                name: child.name,
                itemCode: child.itemCode,
                badges: decodeStorageBadges(child.badgesCSV),
                hideFromBlueprints: child.hideFromBlueprints,
                crafterCount: crafterCountsByItem[childId] ?? 0,
                totalQty: ownQty + nestedChildren.reduce(0) { $0 + $1.totalQty },
                openSearchCount: (openSearchCountsByItem[childId] ?? 0) + nestedChildren.reduce(0) { $0 + $1.openSearchCount },
                entryCount: ownEntryCount + nestedChildren.reduce(0) { $0 + $1.entryCount },
                children: nestedChildren
            )
        }
    }

    let childSummaries = try buildChildSummaries(parentId: itemId)
    let ownCrafterCount = crafterCountsByItem[itemId] ?? 0
    let ownOpenSearchCount = openSearchCountsByItem[itemId] ?? 0
    let ownEntryCount = entryDtos.count
    let ownTotalQty = entryDtos.reduce(0) { $0 + $1.qty }

    return .init(
        id: itemId,
        parentId: item.$parent.id,
        name: item.name,
        description: item.description,
        itemCode: item.itemCode,
        badges: decodeStorageBadges(item.badgesCSV),
        availableBadges: availableBadgeNames(from: badgeDefinitionsDTO),
        badgeDefinitions: badgeDefinitionsDTO,
        hideFromBlueprints: item.hideFromBlueprints,
        crafterCount: ownCrafterCount,
        totalQty: ownTotalQty + childSummaries.reduce(0) { $0 + $1.totalQty },
        openSearchCount: ownOpenSearchCount + childSummaries.reduce(0) { $0 + $1.openSearchCount },
        entryCount: ownEntryCount + childSummaries.reduce(0) { $0 + $1.entryCount },
        breadcrumb: breadcrumb,
        children: childSummaries,
        entries: entryDtos,
        availableUsers: availablePeople(from: users),
        locations: try buildLocationTree(parentId: nil, grouped: groupedLocations),
        locationFilters: locationFilters(from: locations)
    )
}

func listStorageItems(_ req: Request) async throws -> StorageListResponseDTO {
    let actor = try requireNonGuestUser(req)

    let items = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    let locations = try await StorageLocation.query(on: req.db).all()
    let entries = try await StorageEntry.query(on: req.db).all()
    let users = try await User.query(on: req.db).all()
    let crafters = try await BlueprintCrafter.query(on: req.db).all()
    let searchRequests = try await ItemSearchRequest.query(on: req.db).all()
    let badgeDefinitions = try await ItemBadgeDefinition.query(on: req.db).all()
    let badgeDefinitionsDTO = buildBadgeDefinitions(items: items, definitions: badgeDefinitions)

    let usersById = Dictionary(uniqueKeysWithValues: users.compactMap { entry in
        entry.id.map { ($0, entry) }
    })
    let locationsById = Dictionary(uniqueKeysWithValues: locations.compactMap { entry in
        entry.id.map { ($0, entry) }
    })
    let entryDtosWithItemIds = entries.compactMap { entry -> (UUID, StorageEntryResponseDTO)? in
        let itemId = entry.$item.id
        let dtos = entryDTOs(entries: [entry], usersById: usersById, locationsById: locationsById)
        guard let dto = dtos.first else { return nil }
        return (itemId, dto)
    }
    let entriesByItem = Dictionary(grouping: entryDtosWithItemIds, by: { $0.0 }).mapValues { groupedEntries in
        groupedEntries.map { $0.1 }
    }
    let groupedItems = Dictionary(grouping: items, by: { $0.$parent.id })
    let groupedLocations = Dictionary(grouping: locations, by: { $0.$parent.id })
    let latestActivityMap = buildStorageActivityMap(items: items, entries: entries)
    let crafterCountsByItem = Dictionary(grouping: crafters, by: { $0.$blueprint.id }).mapValues(\.count)
    let openSearchCountsByItem = Dictionary(grouping: searchRequests.filter { $0.status == .open }, by: { $0.$item.id }).mapValues(\.count)
    let craftedByActorItemIds = Set(crafters.filter { $0.$user.id == actor.id }.map { $0.$blueprint.id })

    let itemTree = try buildItemTree(
        parentId: nil,
        grouped: groupedItems,
        entriesByItem: entriesByItem,
        latestActivityMap: latestActivityMap,
        crafterCountsByItem: crafterCountsByItem,
        openSearchCountsByItem: openSearchCountsByItem,
        craftedByActorItemIds: craftedByActorItemIds
    )
    let filteredUsers = availablePeople(from: users.filter { user in
        guard let userId = user.id else { return false }
        return entries.contains { $0.$user.id == userId }
    })

    return .init(
        items: itemTree,
        availableBadges: availableBadgeNames(from: badgeDefinitionsDTO),
        badgeDefinitions: badgeDefinitionsDTO,
        availableUsers: filteredUsers,
        locations: try buildLocationTree(parentId: nil, grouped: groupedLocations),
        locationFilters: locationFilters(from: locations)
    )
}

func getStorageItem(_ req: Request) async throws -> StorageItemDetailDTO {
    _ = try requireNonGuestUser(req)
    guard let item = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }

    let items = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    let locations = try await StorageLocation.query(on: req.db).all()
    let entries = try await StorageEntry.query(on: req.db).all()
    let users = try await User.query(on: req.db).all()
    let crafters = try await BlueprintCrafter.query(on: req.db).all()
    let searchRequests = try await ItemSearchRequest.query(on: req.db).all()
    let badgeDefinitions = try await ItemBadgeDefinition.query(on: req.db).all()
    return try storageItemDetail(
        item: item,
        allItems: items,
        badgeDefinitions: badgeDefinitions,
        locations: locations,
        users: users,
        entries: entries,
        crafterCountsByItem: Dictionary(grouping: crafters, by: { $0.$blueprint.id }).mapValues(\.count),
        openSearchCountsByItem: Dictionary(grouping: searchRequests.filter { $0.status == .open }, by: { $0.$item.id }).mapValues(\.count)
    )
}

func createStorageItem(_ req: Request) async throws -> StorageItemDetailDTO {
    let actor = try requireStorageEditor(req)
    let body = try req.content.decode(StorageItemCreateDTO.self)
    let badges = sanitizeStorageBadges(body.badges)
    if body.parentId == nil {
        try requireStorageAdmin(actor)
    }
    if let parentId = body.parentId, try await Blueprint.find(parentId, on: req.db) == nil {
        throw Abort(.badRequest, reason: "Parent item not found")
    }
    try await ensureBadgeDefinitionsExist(badges: badges, actor: actor, on: req.db)

    let item = Blueprint(
        parentID: body.parentId,
        name: try sanitizeStorageName(body.name),
        description: sanitizeStorageDescription(body.description),
        itemCode: sanitizeStorageItemCode(body.itemCode),
        badgesCSV: encodeStorageBadges(badges),
        hideFromBlueprints: canAdminChangeBlueprintVisibility(actor) ? sanitizeStorageHideFromBlueprints(body.hideFromBlueprints) : false,
        category: .blueprints,
        isCraftable: false
    )
    try await item.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "storage.item.create", entityType: "storage_item", entityId: item.id)
    return try await getStorageItemById(item.id, on: req.db)
}

func updateStorageItem(_ req: Request) async throws -> StorageItemDetailDTO {
    let actor = try requireStorageEditor(req)
    guard let item = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(StorageItemUpdateDTO.self)
    let badges = sanitizeStorageBadges(body.badges)
    let itemId = try item.requireID()
    let allItems = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    let grouped = Dictionary(grouping: allItems, by: { $0.$parent.id })

    if body.parentId != item.$parent.id {
        try requireStorageAdmin(actor)
    }

    if let parentId = body.parentId {
        guard let _ = allItems.first(where: { $0.id == parentId }) else {
            throw Abort(.badRequest, reason: "Parent item not found")
        }
        let descendants = collectItemDescendantIds(rootId: itemId, groupedByParent: grouped)
        if parentId == itemId || descendants.contains(parentId) {
            throw Abort(.badRequest, reason: "Invalid item hierarchy")
        }
    }
    try await ensureBadgeDefinitionsExist(badges: badges, actor: actor, on: req.db)

    item.$parent.id = body.parentId
    item.name = try sanitizeStorageName(body.name)
    item.description = sanitizeStorageDescription(body.description)
    item.itemCode = sanitizeStorageItemCode(body.itemCode)
    item.badgesCSV = encodeStorageBadges(badges)
    if canAdminChangeBlueprintVisibility(actor) {
        item.hideFromBlueprints = sanitizeStorageHideFromBlueprints(body.hideFromBlueprints)
    }
    try await item.save(on: req.db)

    await recordAuditEvent(on: req, actor: actor, action: "storage.item.update", entityType: "storage_item", entityId: itemId)
    return try await getStorageItemById(itemId, on: req.db)
}

func deleteStorageItem(_ req: Request) async throws -> HTTPStatus {
    let actor = try requireStorageEditor(req)
    try requireStorageAdmin(actor)
    guard let item = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let itemId = try item.requireID()
    try await item.delete(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "storage.item.delete", entityType: "storage_item", entityId: itemId)
    return .noContent
}

func listStorageLocations(_ req: Request) async throws -> [StorageLocationNodeDTO] {
    _ = try requireNonGuestUser(req)
    let locations = try await StorageLocation.query(on: req.db).all()
    let grouped = Dictionary(grouping: locations, by: { $0.$parent.id })
    return try buildLocationTree(parentId: nil, grouped: grouped)
}

func createStorageLocation(_ req: Request) async throws -> [StorageLocationNodeDTO] {
    let actor = try requireStorageEditor(req)
    let body = try req.content.decode(StorageLocationCreateDTO.self)
    if let parentId = body.parentId, try await StorageLocation.find(parentId, on: req.db) == nil {
        throw Abort(.badRequest, reason: "Parent location not found")
    }
    let location = StorageLocation(parentID: body.parentId, name: try sanitizeStorageName(body.name), description: sanitizeStorageDescription(body.description))
    try await location.save(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "storage.location.create", entityType: "storage_location", entityId: location.id)
    return try await listStorageLocations(req)
}

func updateStorageLocation(_ req: Request) async throws -> [StorageLocationNodeDTO] {
    let actor = try requireStorageEditor(req)
    try requireStorageAdmin(actor)
    guard let location = try await StorageLocation.find(req.parameters.get("locationID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let body = try req.content.decode(StorageLocationUpdateDTO.self)
    let locationId = try location.requireID()
    let allLocations = try await StorageLocation.query(on: req.db).all()
    let grouped = Dictionary(grouping: allLocations, by: { $0.$parent.id })
    if let parentId = body.parentId {
        guard let _ = allLocations.first(where: { $0.id == parentId }) else {
            throw Abort(.badRequest, reason: "Parent location not found")
        }
        let descendants = collectLocationDescendantIds(rootId: locationId, groupedByParent: grouped)
        if parentId == locationId || descendants.contains(parentId) {
            throw Abort(.badRequest, reason: "Invalid location hierarchy")
        }
    }
    location.$parent.id = body.parentId
    location.name = try sanitizeStorageName(body.name)
    location.description = sanitizeStorageDescription(body.description)
    try await location.save(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "storage.location.update", entityType: "storage_location", entityId: locationId)
    return try await listStorageLocations(req)
}

func createItemBadgeDefinition(_ req: Request) async throws -> [ItemBadgeDefinitionDTO] {
    let actor = try requireStorageEditor(req)
    try requireItemBadgeAdmin(actor)
    let body = try req.content.decode(ItemBadgeDefinitionCreateDTO.self)
    let name = try sanitizeItemBadgeName(body.name)
    let groupName = sanitizeItemBadgeGroupName(body.groupName)

    let existing = try await ItemBadgeDefinition.query(on: req.db).all()
    guard !existing.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
        throw Abort(.conflict, reason: "Badge already exists")
    }

    let definition = ItemBadgeDefinition(name: name, groupName: groupName)
    try await definition.save(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "item.badge.create", entityType: "item_badge", entityId: definition.id, details: "name=\(name)")

    let items = try await Blueprint.query(on: req.db).filter(\.$category == .blueprints).all()
    let definitions = try await ItemBadgeDefinition.query(on: req.db).all()
    return buildBadgeDefinitions(items: items, definitions: definitions)
}

func updateItemBadgeDefinition(_ req: Request) async throws -> [ItemBadgeDefinitionDTO] {
    let actor = try requireStorageEditor(req)
    try requireItemBadgeAdmin(actor)
    let body = try req.content.decode(ItemBadgeDefinitionUpdateDTO.self)
    let currentName = try sanitizeItemBadgeName(body.currentName)
    let newName = try sanitizeItemBadgeName(body.newName)
    let groupName = sanitizeItemBadgeGroupName(body.groupName)

    let items = try await Blueprint.query(on: req.db).filter(\.$category == .blueprints).all()
    let definitions = try await ItemBadgeDefinition.query(on: req.db).all()
    let usedBadges = collectBadges(items: items)

    guard usedBadges.contains(where: { $0.caseInsensitiveCompare(currentName) == .orderedSame }) ||
          definitions.contains(where: { $0.name.caseInsensitiveCompare(currentName) == .orderedSame }) else {
        throw Abort(.notFound, reason: "Badge not found")
    }

    guard !definitions.contains(where: {
        $0.name.caseInsensitiveCompare(newName) == .orderedSame &&
        $0.name.caseInsensitiveCompare(currentName) != .orderedSame
    }) else {
        throw Abort(.conflict, reason: "Target badge already exists")
    }

    for item in items {
        let existingBadges = decodeStorageBadges(item.badgesCSV)
        guard existingBadges.contains(where: { $0.caseInsensitiveCompare(currentName) == .orderedSame }) else { continue }
        let updatedBadges = sanitizeStorageBadges(
            existingBadges.map { badge in
                badge.caseInsensitiveCompare(currentName) == .orderedSame ? newName : badge
            }
        )
        item.badgesCSV = encodeStorageBadges(updatedBadges)
        try await item.save(on: req.db)
    }

    if let existingDefinition = definitions.first(where: { $0.name.caseInsensitiveCompare(currentName) == .orderedSame }) {
        existingDefinition.name = newName
        existingDefinition.groupName = groupName
        try await existingDefinition.save(on: req.db)
    } else {
        let definition = ItemBadgeDefinition(name: newName, groupName: groupName)
        try await definition.save(on: req.db)
    }

    await recordAuditEvent(on: req, actor: actor, action: "item.badge.update", entityType: "item_badge", details: "from=\(currentName);to=\(newName);group=\(groupName ?? "")")

    let refreshedItems = try await Blueprint.query(on: req.db).filter(\.$category == .blueprints).all()
    let refreshedDefinitions = try await ItemBadgeDefinition.query(on: req.db).all()
    return buildBadgeDefinitions(items: refreshedItems, definitions: refreshedDefinitions)
}

func deleteItemBadgeDefinition(_ req: Request) async throws -> [ItemBadgeDefinitionDTO] {
    let actor = try requireStorageEditor(req)
    try requireItemBadgeAdmin(actor)
    let body = try req.content.decode(ItemBadgeDefinitionDeleteDTO.self)
    let badgeName = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let groupName = sanitizeItemBadgeGroupName(body.groupName)

    let items = try await Blueprint.query(on: req.db).filter(\.$category == .blueprints).all()
    let definitions = try await ItemBadgeDefinition.query(on: req.db).all()
    if !badgeName.isEmpty {
        let normalizedBadgeName = try sanitizeItemBadgeName(badgeName)

        for item in items {
            let existingBadges = decodeStorageBadges(item.badgesCSV)
            let updatedBadges = existingBadges.filter { $0.caseInsensitiveCompare(normalizedBadgeName) != .orderedSame }
            guard updatedBadges.count != existingBadges.count else { continue }
            item.badgesCSV = encodeStorageBadges(updatedBadges)
            try await item.save(on: req.db)
        }

        for definition in definitions where definition.name.caseInsensitiveCompare(normalizedBadgeName) == .orderedSame {
            try await definition.delete(on: req.db)
        }

        await recordAuditEvent(on: req, actor: actor, action: "item.badge.delete", entityType: "item_badge", details: "name=\(normalizedBadgeName)")
    } else {
        let groupDefinitions = definitions.filter { badgeGroupMatches($0, groupName: groupName) }
        guard !groupDefinitions.isEmpty else {
            throw Abort(.notFound, reason: "Badge group not found")
        }

        let groupBadgeNames = Set(groupDefinitions.map { $0.name.lowercased() })
        for item in items {
            let existingBadges = decodeStorageBadges(item.badgesCSV)
            let updatedBadges = existingBadges.filter { !groupBadgeNames.contains($0.lowercased()) }
            guard updatedBadges.count != existingBadges.count else { continue }
            item.badgesCSV = encodeStorageBadges(updatedBadges)
            try await item.save(on: req.db)
        }

        for definition in groupDefinitions {
            try await definition.delete(on: req.db)
        }

        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "item.badge-group.delete",
            entityType: "item_badge_group",
            details: "group=\(groupName ?? "Ohne Gruppe");count=\(groupDefinitions.count)"
        )
    }

    let refreshedItems = try await Blueprint.query(on: req.db).filter(\.$category == .blueprints).all()
    let refreshedDefinitions = try await ItemBadgeDefinition.query(on: req.db).all()
    return buildBadgeDefinitions(items: refreshedItems, definitions: refreshedDefinitions)
}

func mergeStorageItem(_ req: Request) async throws -> StorageItemDetailDTO {
    let actor = try requireStorageEditor(req)
    try requireStorageAdmin(actor)

    guard let currentItem = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let currentId = try currentItem.requireID()
    let body = try req.content.decode(StorageItemMergeDTO.self)

    guard body.otherItemId != currentId else {
        throw Abort(.badRequest, reason: "Cannot merge an item with itself")
    }
    guard let otherItem = try await Blueprint.find(body.otherItemId, on: req.db) else {
        throw Abort(.badRequest, reason: "Other item not found")
    }

    let keepCurrent = body.keepValuesFrom.uppercased() != "OTHER"
    let primary = keepCurrent ? currentItem : otherItem
    let secondary = keepCurrent ? otherItem : currentItem
    let primaryId = try primary.requireID()
    let secondaryId = try secondary.requireID()

    let targetParentId: UUID?
    switch body.parentChoice.uppercased() {
    case "OTHER":
        targetParentId = otherItem.$parent.id
    case "ROOT":
        targetParentId = nil
    default:
        targetParentId = currentItem.$parent.id
    }

    let allItems = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    let groupedByParent = Dictionary(grouping: allItems, by: { $0.$parent.id })
    let secondaryDescendantIds = collectItemDescendantIds(rootId: secondaryId, groupedByParent: groupedByParent)
    if let targetParentId, (targetParentId == secondaryId || secondaryDescendantIds.contains(targetParentId)) {
        throw Abort(.badRequest, reason: "Selected parent would create an invalid hierarchy")
    }

    primary.$parent.id = targetParentId
    primary.badgesCSV = encodeStorageBadges(
        sanitizeStorageBadges(decodeStorageBadges(primary.badgesCSV) + decodeStorageBadges(secondary.badgesCSV))
    )
    try await primary.save(on: req.db)

    let secondaryChildren = try await Blueprint.query(on: req.db)
        .filter(\.$parent.$id == secondaryId)
        .all()
    for child in secondaryChildren {
        child.$parent.id = primaryId
        try await child.save(on: req.db)
    }

    let secondaryEntries = try await StorageEntry.query(on: req.db)
        .filter(\.$item.$id == secondaryId)
        .all()
    for entry in secondaryEntries {
        entry.$item.id = primaryId
        try await entry.save(on: req.db)
    }

    let existingPrimaryAssignments = try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == primaryId)
        .all()
    let existingPrimaryUserIds = Set(existingPrimaryAssignments.map { $0.$user.id })
    let secondaryAssignments = try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == secondaryId)
        .all()
    for assignment in secondaryAssignments where !existingPrimaryUserIds.contains(assignment.$user.id) {
        let mergedAssignment = BlueprintCrafter(blueprintID: primaryId, userID: assignment.$user.id)
        try await mergedAssignment.save(on: req.db)
    }

    let remainingPrimaryCrafterCount = try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == primaryId)
        .count()
    primary.isCraftable = remainingPrimaryCrafterCount > 0
    try await primary.save(on: req.db)

    try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == secondaryId)
        .delete()

    try await secondary.delete(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "storage.item.merge",
        entityType: "storage_item",
        entityId: primaryId,
        details: "merged=\(secondaryId.uuidString);keepValuesFrom=\(body.keepValuesFrom);parentChoice=\(body.parentChoice)"
    )

    return try await getStorageItemById(primaryId, on: req.db)
}

func deleteStorageLocation(_ req: Request) async throws -> HTTPStatus {
    let actor = try requireStorageEditor(req)
    try requireStorageAdmin(actor)
    guard let location = try await StorageLocation.find(req.parameters.get("locationID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let locationId = try location.requireID()
    try await location.delete(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "storage.location.delete", entityType: "storage_location", entityId: locationId)
    return .noContent
}

func createStorageEntry(_ req: Request) async throws -> StorageItemDetailDTO {
    let actor = try requireStorageEditor(req)
    guard let item = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let body = try req.content.decode(StorageEntryCreateDTO.self)
    guard body.qty > 0 else {
        throw Abort(.badRequest, reason: "qty must be > 0")
    }
    guard try await StorageLocation.find(body.locationId, on: req.db) != nil else {
        throw Abort(.badRequest, reason: "Location not found")
    }

    let targetUserId: UUID
    if actor.role == .admin || actor.role == .superAdmin, let requestedUserId = body.userId {
        guard try await User.find(requestedUserId, on: req.db) != nil else {
            throw Abort(.badRequest, reason: "User not found")
        }
        targetUserId = requestedUserId
    } else {
        targetUserId = try actor.requireID()
    }

    let entry = StorageEntry(itemID: try item.requireID(), locationID: body.locationId, userID: targetUserId, qty: body.qty, note: sanitizeStorageDescription(body.note))
    try await entry.save(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "storage.entry.create", entityType: "storage_item", entityId: item.id, details: "qty=\(body.qty)")
    return try await getStorageItemById(item.id, on: req.db)
}

func deleteStorageEntry(_ req: Request) async throws -> StorageItemDetailDTO {
    let actor = try requireStorageEditor(req)
    guard let entry = try await StorageEntry.find(req.parameters.get("entryID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let itemId = entry.$item.id
    if actor.role != .admin && actor.role != .superAdmin && actor.id != entry.$user.id {
        throw Abort(.forbidden)
    }
    try await entry.delete(on: req.db)
    await recordAuditEvent(on: req, actor: actor, action: "storage.entry.delete", entityType: "storage_item", entityId: itemId)
    return try await getStorageItemById(itemId, on: req.db)
}

func updateStorageEntry(_ req: Request) async throws -> StorageItemDetailDTO {
    let actor = try requireStorageEditor(req)
    guard let entry = try await StorageEntry.find(req.parameters.get("entryID"), on: req.db) else {
        throw Abort(.notFound)
    }

    if actor.role != .admin && actor.role != .superAdmin && actor.id != entry.$user.id {
        throw Abort(.forbidden)
    }

    let body = try req.content.decode(StorageEntryUpdateDTO.self)
    guard body.qty > 0 else {
        throw Abort(.badRequest, reason: "qty must be > 0")
    }

    entry.qty = body.qty
    entry.note = sanitizeStorageDescription(body.note)
    try await entry.save(on: req.db)

    let itemId = entry.$item.id
    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "storage.entry.update",
        entityType: "storage_item",
        entityId: itemId,
        details: "qty=\(body.qty)"
    )
    return try await getStorageItemById(itemId, on: req.db)
}

private func getStorageItemById(_ itemId: UUID?, on db: Database) async throws -> StorageItemDetailDTO {
    guard let itemId, let item = try await Blueprint.find(itemId, on: db) else {
        throw Abort(.notFound)
    }
    let allItems = try await Blueprint.query(on: db)
        .filter(\.$category == .blueprints)
        .all()
    let locations = try await StorageLocation.query(on: db).all()
    let entries = try await StorageEntry.query(on: db).all()
    let users = try await User.query(on: db).all()
    let crafters = try await BlueprintCrafter.query(on: db).all()
    let searchRequests = try await ItemSearchRequest.query(on: db).all()
    let badgeDefinitions = try await ItemBadgeDefinition.query(on: db).all()
    return try storageItemDetail(
        item: item,
        allItems: allItems,
        badgeDefinitions: badgeDefinitions,
        locations: locations,
        users: users,
        entries: entries,
        crafterCountsByItem: Dictionary(grouping: crafters, by: { $0.$blueprint.id }).mapValues(\.count),
        openSearchCountsByItem: Dictionary(grouping: searchRequests.filter { $0.status == .open }, by: { $0.$item.id }).mapValues(\.count)
    )
}
