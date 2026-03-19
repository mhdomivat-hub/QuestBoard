import Vapor
import Fluent

private func requireBlueprintEditor(_ req: Request) throws -> User {
    let user = try requireAuthenticatedUser(req)
    if user.role == .guest {
        throw Abort(.forbidden, reason: "Guests may only view blueprints")
    }
    return user
}

private func requireBlueprintStructureEditor(_ user: User) throws {
    guard user.role == .admin || user.role == .superAdmin else {
        throw Abort(.forbidden, reason: "Only admins may change blueprint structure")
    }
}

private func requireBlueprintBadgeAdmin(_ user: User) throws {
    guard user.role == .admin || user.role == .superAdmin else {
        throw Abort(.forbidden, reason: "Only admins may manage blueprint badges")
    }
}

private func requireBlueprintAdmin(_ user: User) throws {
    guard user.role == .admin || user.role == .superAdmin else {
        throw Abort(.forbidden, reason: "Only admins may manage top-level blueprints")
    }
}

private func sanitizeBlueprintName(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw Abort(.badRequest, reason: "Name required")
    }
    guard trimmed.count <= 120 else {
        throw Abort(.badRequest, reason: "Name too long")
    }
    return trimmed
}

private func sanitizeBlueprintDescription(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func sanitizeBlueprintItemCode(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(160))
}

private func sanitizeBlueprintBadges(_ values: [String]?) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []

    for raw in values ?? [] {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }
        let normalized = String(value.prefix(32))
        let key = normalized.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(normalized)
        if result.count >= 8 { break }
    }

    return result
}

private func sanitizeBlueprintBadge(_ value: String) throws -> String {
    let sanitized = sanitizeBlueprintBadges([value])
    guard let first = sanitized.first else {
        throw Abort(.badRequest, reason: "Badge required")
    }
    return first
}

private func encodeBlueprintBadges(_ badges: [String]) -> String? {
    guard !badges.isEmpty else { return nil }
    return badges.joined(separator: ",")
}

private func decodeBlueprintBadges(_ raw: String?) -> [String] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func loadBlueprintContext(on db: Database) async throws -> ([Blueprint], [BlueprintCrafter], [UUID: User]) {
    let blueprints = try await Blueprint.query(on: db)
        .sort(\.$name, .ascending)
        .all()

    let assignments = try await BlueprintCrafter.query(on: db)
        .with(\.$user)
        .all()

    var usersById: [UUID: User] = [:]
    for assignment in assignments {
        if let userID = assignment.user.id {
            usersById[userID] = assignment.user
        }
    }

    return (blueprints, assignments, usersById)
}

private func buildCrafterMap(
    _ assignments: [BlueprintCrafter],
    usersById: [UUID: User]
) -> [UUID: [BlueprintCrafterResponseDTO]] {
    var result: [UUID: [BlueprintCrafterResponseDTO]] = [:]
    for assignment in assignments {
        let blueprintID = assignment.$blueprint.id
        let userID = assignment.$user.id
        guard let user = usersById[userID], let resolvedUserID = user.id else { continue }
        result[blueprintID, default: []].append(.init(userId: resolvedUserID, username: user.username))
    }

    for key in result.keys {
        result[key] = result[key]?.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
    }
    return result
}

private func buildBlueprintActivityMap(
    blueprints: [Blueprint],
    assignments: [BlueprintCrafter],
    storageEntries: [StorageEntry]
) -> [UUID: Date] {
    var result: [UUID: Date] = [:]

    func register(_ date: Date?, for blueprintId: UUID) {
        guard let date else { return }
        if let existing = result[blueprintId], existing >= date {
            return
        }
        result[blueprintId] = date
    }

    for blueprint in blueprints {
        guard let blueprintId = blueprint.id else { continue }
        register(blueprint.createdAt, for: blueprintId)
        register(blueprint.updatedAt, for: blueprintId)
    }

    for assignment in assignments {
        register(assignment.createdAt, for: assignment.$blueprint.id)
    }

    for entry in storageEntries {
        register(entry.createdAt, for: entry.$item.id)
    }

    return result
}

private func collectAvailableBadges(_ blueprints: [Blueprint]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []

    for badge in blueprints.flatMap({ decodeBlueprintBadges($0.badgesCSV) }) {
        let key = badge.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(badge)
    }

    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func ensureBadgeCreationAllowed(actor: User, badges: [String], existingBadges: [String]) throws {
    guard actor.role != .admin && actor.role != .superAdmin else { return }
    let existingSet = Set(existingBadges.map { $0.lowercased() })
    let introducingNewBadge = badges.contains { !existingSet.contains($0.lowercased()) }
    if introducingNewBadge {
        throw Abort(.forbidden, reason: "Only admins may create new badges")
    }
}

private func collectDescendantIds(rootId: UUID, groupedByParent: [UUID?: [Blueprint]]) -> Set<UUID> {
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

private func updateBlueprintSubtreeCategory(rootId: UUID, category: BlueprintCategory, on db: Database) async throws {
    let allBlueprints = try await Blueprint.query(on: db).all()
    let groupedByParent = Dictionary(grouping: allBlueprints, by: { $0.$parent.id })
    let descendantIds = collectDescendantIds(rootId: rootId, groupedByParent: groupedByParent)
    guard !descendantIds.isEmpty else { return }

    let descendants = try await Blueprint.query(on: db)
        .filter(\.$id ~~ Array(descendantIds))
        .all()

    for descendant in descendants {
        descendant.category = category
        try await descendant.save(on: db)
    }
}

private func buildBlueprintTree(
    parentId: UUID?,
    grouped: [UUID?: [Blueprint]],
    crafterMap: [UUID: [BlueprintCrafterResponseDTO]],
    latestActivityMap: [UUID: Date]
) throws -> [BlueprintTreeNodeDTO] {
    let nodes = (grouped[parentId] ?? []).sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }

    return try nodes.map { node in
        guard let nodeID = node.id else { throw Abort(.internalServerError) }
        return .init(
            id: nodeID,
            parentId: node.$parent.id,
            name: node.name,
            description: node.description,
            itemCode: node.itemCode,
            createdAt: node.createdAt,
            latestActivityAt: latestActivityMap[nodeID],
            badges: decodeBlueprintBadges(node.badgesCSV),
            category: node.category,
            isCraftable: node.isCraftable,
            crafters: crafterMap[nodeID] ?? [],
            children: try buildBlueprintTree(
                parentId: nodeID,
                grouped: grouped,
                crafterMap: crafterMap,
                latestActivityMap: latestActivityMap
            )
        )
    }
}

private func blueprintDetailDTO(
    blueprint: Blueprint,
    byId: [UUID: Blueprint],
    groupedByParent: [UUID?: [Blueprint]],
    children: [Blueprint],
    crafterMap: [UUID: [BlueprintCrafterResponseDTO]],
    availableBadges: [String]
) throws -> BlueprintDetailResponseDTO {
    guard let blueprintID = blueprint.id else { throw Abort(.internalServerError) }

    var breadcrumbIds: [UUID] = []
    var currentParentId = blueprint.$parent.id
    while let parentId = currentParentId, let parent = byId[parentId] {
        breadcrumbIds.insert(parentId, at: 0)
        currentParentId = parent.$parent.id
    }

    let breadcrumb = breadcrumbIds.compactMap { id -> BlueprintBreadcrumbItemDTO? in
        guard let item = byId[id] else { return nil }
        return .init(id: id, name: item.name)
    } + [.init(id: blueprintID, name: blueprint.name)]

    let childDtos = try children
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .map { child in
            guard let childID = child.id else { throw Abort(.internalServerError) }
            return BlueprintChildSummaryDTO(
                id: childID,
                name: child.name,
                itemCode: child.itemCode,
                badges: decodeBlueprintBadges(child.badgesCSV),
                category: child.category,
                isCraftable: child.isCraftable,
                childCount: groupedByParent[childID]?.count ?? 0,
                crafterCount: crafterMap[childID]?.count ?? 0
            )
        }

    return .init(
        id: blueprintID,
        parentId: blueprint.$parent.id,
        name: blueprint.name,
        description: blueprint.description,
        itemCode: blueprint.itemCode,
        badges: decodeBlueprintBadges(blueprint.badgesCSV),
        availableBadges: availableBadges,
        category: blueprint.category,
        isCraftable: blueprint.isCraftable,
        breadcrumb: breadcrumb,
        children: childDtos,
        crafters: crafterMap[blueprintID] ?? []
    )
}

func listBlueprints(_ req: Request) async throws -> BlueprintListResponseDTO {
    _ = try requireNonGuestUser(req)

    let (blueprints, assignments, usersById) = try await loadBlueprintContext(on: req.db)
    let storageEntries = try await StorageEntry.query(on: req.db).all()
    let crafterMap = buildCrafterMap(assignments, usersById: usersById)
    let latestActivityMap = buildBlueprintActivityMap(
        blueprints: blueprints,
        assignments: assignments,
        storageEntries: storageEntries
    )
    let groupedByParent = Dictionary(grouping: blueprints, by: { $0.$parent.id })
    let roots = blueprints.filter { $0.$parent.id == nil && $0.category == .blueprints }

    let tree = try roots
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .map { root in
            guard let rootID = root.id else { throw Abort(.internalServerError) }
            return BlueprintTreeNodeDTO(
                id: rootID,
                parentId: nil,
                name: root.name,
                description: root.description,
                itemCode: root.itemCode,
                createdAt: root.createdAt,
                latestActivityAt: latestActivityMap[rootID],
                badges: decodeBlueprintBadges(root.badgesCSV),
                category: root.category,
                isCraftable: root.isCraftable,
                crafters: crafterMap[rootID] ?? [],
                children: try buildBlueprintTree(
                    parentId: rootID,
                    grouped: groupedByParent,
                    crafterMap: crafterMap,
                    latestActivityMap: latestActivityMap
                )
            )
        }

    return .init(
        blueprints: tree,
        availableBadges: collectAvailableBadges(blueprints)
    )
}

func getBlueprint(_ req: Request) async throws -> BlueprintDetailResponseDTO {
    _ = try requireNonGuestUser(req)

    guard let blueprint = try await Blueprint.find(req.parameters.get("blueprintID"), on: req.db) else {
        throw Abort(.notFound)
    }

    return try await getBlueprintById(blueprint.id, on: req.db)
}

func createBlueprint(_ req: Request) async throws -> BlueprintDetailResponseDTO {
    let actor = try requireBlueprintEditor(req)
    let body = try req.content.decode(BlueprintCreateDTO.self)
    let (blueprints, _, _) = try await loadBlueprintContext(on: req.db)
    let badges = sanitizeBlueprintBadges(body.badges)
    try ensureBadgeCreationAllowed(actor: actor, badges: badges, existingBadges: collectAvailableBadges(blueprints))

    let resolvedCategory: BlueprintCategory
    if let parentId = body.parentId {
        guard let parent = try await Blueprint.find(parentId, on: req.db) else {
            throw Abort(.badRequest, reason: "Parent blueprint not found")
        }
        resolvedCategory = parent.category
    } else {
        try requireBlueprintAdmin(actor)
        resolvedCategory = .blueprints
    }

    let blueprint = Blueprint(
        parentID: body.parentId,
        name: try sanitizeBlueprintName(body.name),
        description: sanitizeBlueprintDescription(body.description),
        itemCode: sanitizeBlueprintItemCode(body.itemCode),
        badgesCSV: encodeBlueprintBadges(badges),
        category: resolvedCategory,
        isCraftable: false
    )
    try await blueprint.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.create",
        entityType: "blueprint",
        entityId: blueprint.id,
        details: "name=\(blueprint.name);category=\(blueprint.category.rawValue)"
    )

    return try await getBlueprintById(blueprint.id, on: req.db)
}

func updateBlueprint(_ req: Request) async throws -> BlueprintDetailResponseDTO {
    let actor = try requireBlueprintEditor(req)
    guard let blueprint = try await Blueprint.find(req.parameters.get("blueprintID"), on: req.db) else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(BlueprintUpdateDTO.self)
    let blueprintId = try blueprint.requireID()
    let previousCategory = blueprint.category
    let previousParentId = blueprint.$parent.id
    let allBlueprints = try await Blueprint.query(on: req.db).all()
    let groupedByParent = Dictionary(grouping: allBlueprints, by: { $0.$parent.id })
    let badges = sanitizeBlueprintBadges(body.badges)
    try ensureBadgeCreationAllowed(actor: actor, badges: badges, existingBadges: collectAvailableBadges(allBlueprints))

    let parentChanged = body.parentId != previousParentId
    if parentChanged {
        try requireBlueprintStructureEditor(actor)
    }

    let resolvedCategory: BlueprintCategory
    if let parentId = body.parentId {
        guard let parent = allBlueprints.first(where: { $0.id == parentId }) else {
            throw Abort(.badRequest, reason: "Parent blueprint not found")
        }
        let descendantIds = collectDescendantIds(rootId: blueprintId, groupedByParent: groupedByParent)
        if parentId == blueprintId || descendantIds.contains(parentId) {
            throw Abort(.badRequest, reason: "Cannot move blueprint into itself or one of its descendants")
        }
        blueprint.$parent.id = parentId
        resolvedCategory = parent.category
    } else {
        blueprint.$parent.id = nil
        resolvedCategory = .blueprints
    }

    blueprint.name = try sanitizeBlueprintName(body.name)
    blueprint.description = sanitizeBlueprintDescription(body.description)
    blueprint.itemCode = sanitizeBlueprintItemCode(body.itemCode)
    blueprint.badgesCSV = encodeBlueprintBadges(badges)
    blueprint.category = resolvedCategory
    try await blueprint.save(on: req.db)

    if previousCategory != resolvedCategory {
        try await updateBlueprintSubtreeCategory(rootId: blueprintId, category: resolvedCategory, on: req.db)
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.update",
        entityType: "blueprint",
        entityId: blueprint.id,
        details: "name=\(blueprint.name);category=\(blueprint.category.rawValue);parentId=\(body.parentId?.uuidString ?? "root")"
    )

    return try await getBlueprintById(blueprintId, on: req.db)
}

func addBlueprintCrafter(_ req: Request) async throws -> BlueprintDetailResponseDTO {
    let actor = try requireBlueprintEditor(req)
    guard let blueprint = try await Blueprint.find(req.parameters.get("blueprintID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard let blueprintID = blueprint.id else {
        throw Abort(.internalServerError)
    }

    let body = try? req.content.decode(BlueprintAssignCrafterDTO.self)
    let targetUserId: UUID
    if actor.role == .admin || actor.role == .superAdmin {
        if let requestedUserId = body?.userId {
            targetUserId = requestedUserId
        } else {
            targetUserId = try actor.requireID()
        }
    } else {
        targetUserId = try actor.requireID()
    }

    guard let targetUser = try await User.find(targetUserId, on: req.db) else {
        throw Abort(.badRequest, reason: "User not found")
    }

    let existing = try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == blueprintID)
        .filter(\.$user.$id == targetUserId)
        .first()

    if existing == nil {
        let crafter = BlueprintCrafter(blueprintID: blueprintID, userID: targetUserId)
        try await crafter.save(on: req.db)
        blueprint.isCraftable = true
        try await blueprint.save(on: req.db)

        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "blueprint.crafter.add",
            entityType: "blueprint",
            entityId: blueprintID,
            details: "username=\(targetUser.username)"
        )
    }

    return try await getBlueprintById(blueprintID, on: req.db)
}

func removeBlueprintCrafter(_ req: Request) async throws -> BlueprintDetailResponseDTO {
    let actor = try requireBlueprintEditor(req)
    guard let blueprint = try await Blueprint.find(req.parameters.get("blueprintID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard let blueprintID = blueprint.id else {
        throw Abort(.internalServerError)
    }
    guard let userId = req.parameters.get("userID", as: UUID.self) else {
        throw Abort(.badRequest)
    }

    if actor.role != .admin && actor.role != .superAdmin && userId != actor.id {
        throw Abort(.forbidden, reason: "You may only remove yourself")
    }

    guard let targetUser = try await User.find(userId, on: req.db) else {
        throw Abort(.badRequest, reason: "User not found")
    }

    try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == blueprintID)
        .filter(\.$user.$id == userId)
        .delete()

    let remainingCrafterCount = try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == blueprintID)
        .count()
    blueprint.isCraftable = remainingCrafterCount > 0
    try await blueprint.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.crafter.remove",
        entityType: "blueprint",
        entityId: blueprintID,
        details: "username=\(targetUser.username)"
    )

    return try await getBlueprintById(blueprintID, on: req.db)
}

func renameBlueprintBadge(_ req: Request) async throws -> BlueprintListResponseDTO {
    let actor = try requireBlueprintEditor(req)
    try requireBlueprintBadgeAdmin(actor)

    let body = try req.content.decode(BlueprintRenameBadgeDTO.self)
    let fromBadge = try sanitizeBlueprintBadge(body.from)
    let toBadge = try sanitizeBlueprintBadge(body.to)

    guard fromBadge.caseInsensitiveCompare(toBadge) != .orderedSame else {
        throw Abort(.badRequest, reason: "Badge name unchanged")
    }

    let blueprints = try await Blueprint.query(on: req.db).all()
    var changedCount = 0

    for blueprint in blueprints {
        let existingBadges = decodeBlueprintBadges(blueprint.badgesCSV)
        guard existingBadges.contains(where: { $0.caseInsensitiveCompare(fromBadge) == .orderedSame }) else {
            continue
        }

        let updatedBadges = sanitizeBlueprintBadges(
            existingBadges.map { badge in
                badge.caseInsensitiveCompare(fromBadge) == .orderedSame ? toBadge : badge
            }
        )
        blueprint.badgesCSV = encodeBlueprintBadges(updatedBadges)
        try await blueprint.save(on: req.db)
        changedCount += 1
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.badge.rename",
        entityType: "blueprint_badge",
        entityId: nil,
        details: "from=\(fromBadge);to=\(toBadge);affected=\(changedCount)"
    )

    return try await listBlueprints(req)
}

func deleteBlueprintBadge(_ req: Request) async throws -> BlueprintListResponseDTO {
    let actor = try requireBlueprintEditor(req)
    try requireBlueprintBadgeAdmin(actor)

    let body = try req.content.decode(BlueprintDeleteBadgeDTO.self)
    let badgeToDelete = try sanitizeBlueprintBadge(body.badge)
    let blueprints = try await Blueprint.query(on: req.db).all()
    var changedCount = 0

    for blueprint in blueprints {
        let existingBadges = decodeBlueprintBadges(blueprint.badgesCSV)
        let updatedBadges = existingBadges.filter {
            $0.caseInsensitiveCompare(badgeToDelete) != .orderedSame
        }
        guard updatedBadges.count != existingBadges.count else { continue }

        blueprint.badgesCSV = encodeBlueprintBadges(updatedBadges)
        try await blueprint.save(on: req.db)
        changedCount += 1
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.badge.delete",
        entityType: "blueprint_badge",
        entityId: nil,
        details: "badge=\(badgeToDelete);affected=\(changedCount)"
    )

    return try await listBlueprints(req)
}

func mergeBlueprint(_ req: Request) async throws -> BlueprintDetailResponseDTO {
    let actor = try requireBlueprintEditor(req)
    try requireBlueprintAdmin(actor)

    guard let currentBlueprint = try await Blueprint.find(req.parameters.get("blueprintID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let currentId = try currentBlueprint.requireID()
    let body = try req.content.decode(BlueprintMergeDTO.self)

    guard body.otherBlueprintId != currentId else {
        throw Abort(.badRequest, reason: "Cannot merge a blueprint with itself")
    }
    guard let otherBlueprint = try await Blueprint.find(body.otherBlueprintId, on: req.db) else {
        throw Abort(.badRequest, reason: "Other blueprint not found")
    }

    let keepCurrent = body.keepValuesFrom.uppercased() != "OTHER"
    let primary = keepCurrent ? currentBlueprint : otherBlueprint
    let secondary = keepCurrent ? otherBlueprint : currentBlueprint
    let primaryId = try primary.requireID()
    let secondaryId = try secondary.requireID()

    let targetParentId: UUID?
    switch body.parentChoice.uppercased() {
    case "OTHER":
        targetParentId = otherBlueprint.$parent.id
    case "ROOT":
        targetParentId = nil
    default:
        targetParentId = currentBlueprint.$parent.id
    }

    let allBlueprints = try await Blueprint.query(on: req.db).all()
    let groupedByParent = Dictionary(grouping: allBlueprints, by: { $0.$parent.id })
    let secondaryDescendantIds = collectDescendantIds(rootId: secondaryId, groupedByParent: groupedByParent)
    if let targetParentId, (targetParentId == secondaryId || secondaryDescendantIds.contains(targetParentId)) {
        throw Abort(.badRequest, reason: "Selected parent would create an invalid hierarchy")
    }

    primary.$parent.id = targetParentId
    primary.badgesCSV = encodeBlueprintBadges(
        sanitizeBlueprintBadges(decodeBlueprintBadges(primary.badgesCSV) + decodeBlueprintBadges(secondary.badgesCSV))
    )
    primary.isCraftable = primary.isCraftable || secondary.isCraftable
    try await primary.save(on: req.db)

    let secondaryChildren = try await Blueprint.query(on: req.db)
        .filter(\.$parent.$id == secondaryId)
        .all()
    for child in secondaryChildren {
        child.$parent.id = primaryId
        try await child.save(on: req.db)
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

    let secondaryStorageEntries = try await StorageEntry.query(on: req.db)
        .filter(\.$item.$id == secondaryId)
        .all()
    for entry in secondaryStorageEntries {
        entry.$item.id = primaryId
        try await entry.save(on: req.db)
    }

    try await BlueprintCrafter.query(on: req.db)
        .filter(\.$blueprint.$id == secondaryId)
        .delete()
    try await secondary.delete(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.merge",
        entityType: "blueprint",
        entityId: primaryId,
        details: "merged=\(secondaryId.uuidString);keepValuesFrom=\(body.keepValuesFrom);parentChoice=\(body.parentChoice)"
    )

    return try await getBlueprintById(primaryId, on: req.db)
}

func deleteBlueprint(_ req: Request) async throws -> HTTPStatus {
    let actor = try requireBlueprintEditor(req)
    try requireBlueprintAdmin(actor)

    guard let blueprint = try await Blueprint.find(req.parameters.get("blueprintID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let blueprintId = try blueprint.requireID()
    try await blueprint.delete(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "blueprint.delete",
        entityType: "blueprint",
        entityId: blueprintId
    )

    return .noContent
}

private func getBlueprintById(_ blueprintId: UUID?, on db: Database) async throws -> BlueprintDetailResponseDTO {
    guard let blueprintId, let blueprint = try await Blueprint.find(blueprintId, on: db) else {
        throw Abort(.notFound)
    }

    let (blueprints, assignments, usersById) = try await loadBlueprintContext(on: db)
    let byId = Dictionary(uniqueKeysWithValues: blueprints.compactMap { item in
        item.id.map { ($0, item) }
    })
    let groupedByParent = Dictionary(grouping: blueprints, by: { $0.$parent.id })
    let crafterMap = buildCrafterMap(assignments, usersById: usersById)
    let children = blueprints.filter { $0.$parent.id == blueprint.id }

    return try blueprintDetailDTO(
        blueprint: blueprint,
        byId: byId,
        groupedByParent: groupedByParent,
        children: children,
        crafterMap: crafterMap,
        availableBadges: collectAvailableBadges(blueprints)
    )
}
