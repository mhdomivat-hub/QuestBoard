import Vapor
import Fluent

private func requireItemSearchUser(_ req: Request) throws -> User {
    try requireNonGuestUser(req)
}

private func decodeItemSearchBadges(_ raw: String?) -> [String] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func collectItemSearchBadges(_ items: [Blueprint]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for badge in items.flatMap({ decodeItemSearchBadges($0.badgesCSV) }) {
        let key = badge.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(badge)
    }
    return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

private func sanitizeItemSearchText(_ value: String?, maxLength: Int) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(maxLength))
}

private func sanitizeItemSearchQty(_ value: Int?) throws -> Int {
    let qty = value ?? 1
    guard qty > 0 else {
        throw Abort(.badRequest, reason: "qty must be > 0")
    }
    return qty
}

private func normalizedItemSearchMatchKey(itemCode: String?, name: String) -> String {
    let code = itemCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if !code.isEmpty { return "code:\(code)" }
    let normalizedName = normalizedItemSearchName(name)
    return "name:\(normalizedName)"
}

private func normalizedItemSearchName(_ value: String) -> String {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let alphanumericOnly = lowered.unicodeScalars.map { scalar -> String in
        CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
    }.joined()
    let collapsed = alphanumericOnly
        .split(separator: " ")
        .map(String.init)
        .filter { token in
            !["rifle", "weapon", "gun"].contains(token)
        }
        .joined(separator: " ")
    return collapsed.replacingOccurrences(of: " ", with: "")
}

private func normalizedItemSearchNote(_ note: String?) -> String {
    (note ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func itemSearchNotesMatch(requestNote: String?, entryNote: String?) -> Bool {
    let normalizedRequest = normalizedItemSearchNote(requestNote)
    let normalizedEntry = normalizedItemSearchNote(entryNote)
    if normalizedRequest.isEmpty || normalizedEntry.isEmpty {
        return true
    }
    return normalizedRequest.contains(normalizedEntry) || normalizedEntry.contains(normalizedRequest)
}

private func itemSearchItemsMatch(requestItem: Blueprint, entryItem: Blueprint) -> Bool {
    let requestCode = requestItem.itemCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    let entryCode = entryItem.itemCode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    if !requestCode.isEmpty && !entryCode.isEmpty {
        return requestCode == entryCode
    }

    let requestName = normalizedItemSearchName(requestItem.name)
    let entryName = normalizedItemSearchName(entryItem.name)
    if requestName.isEmpty || entryName.isEmpty {
        return false
    }
    return requestName == entryName || requestName.contains(entryName) || entryName.contains(requestName)
}

private func buildItemSearchLocationLabel(locationId: UUID, byId: [UUID: StorageLocation]) -> String {
    var names: [String] = []
    var currentId: UUID? = locationId
    while let id = currentId, let location = byId[id] {
        names.insert(location.name, at: 0)
        currentId = location.$parent.id
    }
    return names.joined(separator: " > ")
}

private func canManageItemSearchRequest(_ actor: User, request: ItemSearchRequest) -> Bool {
    actor.role == .admin || actor.role == .superAdmin || actor.id == request.$user.id
}

private func buildItemSearchOfferMap(
    offers: [ItemSearchOffer],
    usersById: [UUID: User]
) -> [UUID: [ItemSearchOfferResponseDTO]] {
    var result: [UUID: [ItemSearchOfferResponseDTO]] = [:]
    for offer in offers {
        guard let offerId = offer.id,
              let user = usersById[offer.$user.id],
              let userId = user.id else {
            continue
        }

        result[offer.$request.id, default: []].append(
            .init(
                id: offerId,
                userId: userId,
                username: user.username,
                note: offer.note,
                hasResources: offer.hasResources,
                createdAt: offer.createdAt
            )
        )
    }

    for key in result.keys {
        result[key] = result[key]?.sorted {
            ($0.createdAt?.timeIntervalSince1970 ?? 0) > ($1.createdAt?.timeIntervalSince1970 ?? 0)
        }
    }

    return result
}

private func buildItemSearchRequestMap(
    requests: [ItemSearchRequest],
    usersById: [UUID: User],
    offerMap: [UUID: [ItemSearchOfferResponseDTO]]
) -> [UUID: [ItemSearchRequestResponseDTO]] {
    var result: [UUID: [ItemSearchRequestResponseDTO]] = [:]
    for request in requests {
        guard let requestId = request.id,
              let user = usersById[request.$user.id],
              let userId = user.id else {
            continue
        }

        result[request.$item.id, default: []].append(
            .init(
                id: requestId,
                userId: userId,
                username: user.username,
                qty: request.qty,
                averageQuality: request.averageQuality,
                note: request.note,
                hasResources: request.hasResources,
                status: request.status,
                createdAt: request.createdAt,
                offers: offerMap[requestId] ?? []
            )
        )
    }

    for key in result.keys {
        result[key] = result[key]?.sorted {
            ($0.createdAt?.timeIntervalSince1970 ?? 0) > ($1.createdAt?.timeIntervalSince1970 ?? 0)
        }
    }

    return result
}

private func buildItemSearchTree(
    parentId: UUID?,
    grouped: [UUID?: [Blueprint]],
    requestsByItem: [UUID: [ItemSearchRequestResponseDTO]],
    crafterCountsByItem: [UUID: Int],
    entryQtyByItem: [UUID: Int]
) throws -> [ItemSearchTreeNodeDTO] {
    let nodes = (grouped[parentId] ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    return try nodes.map { node in
        guard let nodeId = node.id else { throw Abort(.internalServerError) }
        let children = try buildItemSearchTree(
            parentId: nodeId,
            grouped: grouped,
            requestsByItem: requestsByItem,
            crafterCountsByItem: crafterCountsByItem,
            entryQtyByItem: entryQtyByItem
        )
        let openRequests = requestsByItem[nodeId]?.filter { $0.status == .open } ?? []
        let openRequestCount = openRequests.count + children.reduce(0) { $0 + $1.openRequestCount }
        let offerCount = openRequests.reduce(0) { $0 + $1.offers.count } + children.reduce(0) { $0 + $1.offerCount }
        let crafterCount = (crafterCountsByItem[nodeId] ?? 0) + children.reduce(0) { $0 + $1.crafterCount }
        let totalQty = (entryQtyByItem[nodeId] ?? 0) + children.reduce(0) { $0 + $1.totalQty }

        return .init(
            id: nodeId,
            parentId: node.$parent.id,
            name: node.name,
            description: node.description,
            itemCode: node.itemCode,
            badges: decodeItemSearchBadges(node.badgesCSV),
            openRequestCount: openRequestCount,
            offerCount: offerCount,
            crafterCount: crafterCount,
            totalQty: totalQty,
            children: children
        )
    }
}

func listItemSearchItems(_ req: Request) async throws -> ItemSearchListResponseDTO {
    _ = try requireItemSearchUser(req)

    let items = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    let requests = try await ItemSearchRequest.query(on: req.db).all()
    let offers = try await ItemSearchOffer.query(on: req.db).all()
    let users = try await User.query(on: req.db).all()
    let crafters = try await BlueprintCrafter.query(on: req.db).all()
    let entries = try await StorageEntry.query(on: req.db).all()

    let usersById = Dictionary(uniqueKeysWithValues: users.compactMap { user in
        user.id.map { ($0, user) }
    })
    let offerMap = buildItemSearchOfferMap(offers: offers, usersById: usersById)
    let requestMap = buildItemSearchRequestMap(requests: requests, usersById: usersById, offerMap: offerMap)
    let grouped = Dictionary(grouping: items, by: { $0.$parent.id })
    var crafterCountsByItem: [UUID: Int] = [:]
    for crafter in crafters {
        crafterCountsByItem[crafter.$blueprint.id, default: 0] += 1
    }

    var entryQtyByItem: [UUID: Int] = [:]
    for entry in entries {
        entryQtyByItem[entry.$item.id, default: 0] += entry.qty
    }

    return .init(
        items: try buildItemSearchTree(
            parentId: nil,
            grouped: grouped,
            requestsByItem: requestMap,
            crafterCountsByItem: crafterCountsByItem,
            entryQtyByItem: entryQtyByItem
        ),
        availableBadges: collectItemSearchBadges(items)
    )
}

func getItemSearchItem(_ req: Request) async throws -> ItemSearchDetailResponseDTO {
    _ = try requireItemSearchUser(req)
    guard let item = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }

    return try await getItemSearchItemById(item.id, on: req.db)
}

func createItemSearchRequest(_ req: Request) async throws -> ItemSearchDetailResponseDTO {
    let actor = try requireItemSearchUser(req)
    guard let item = try await Blueprint.find(req.parameters.get("itemID"), on: req.db) else {
        throw Abort(.notFound)
    }

    let body = try req.content.decode(ItemSearchRequestCreateDTO.self)
    let request = ItemSearchRequest(
        itemID: try item.requireID(),
        userID: try actor.requireID(),
        qty: try sanitizeItemSearchQty(body.qty),
        averageQuality: sanitizeItemSearchText(body.averageQuality, maxLength: 120),
        note: sanitizeItemSearchText(body.note, maxLength: 1000)
    )
    try await request.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "item-search.request.create",
        entityType: "item_search_request",
        entityId: request.id,
        details: "itemId=\(try item.requireID().uuidString)"
    )

    return try await getItemSearchItemById(item.id, on: req.db)
}

func listMyInventoryMatches(_ req: Request) async throws -> [InventoryMatchResponseDTO] {
    let actor = try requireItemSearchUser(req)
    let actorId = try actor.requireID()

    let openRequests = try await ItemSearchRequest.query(on: req.db)
        .filter(\.$status == .open)
        .all()
    let myEntries = try await StorageEntry.query(on: req.db)
        .filter(\.$user.$id == actorId)
        .all()
    let items = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    let users = try await User.query(on: req.db).all()
    let locations = try await StorageLocation.query(on: req.db).all()

    let itemsById = Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.id.map { ($0, item) }
    })
    let usersById = Dictionary(uniqueKeysWithValues: users.compactMap { user in
        user.id.map { ($0, user) }
    })
    let locationsById = Dictionary(uniqueKeysWithValues: locations.compactMap { location in
        location.id.map { ($0, location) }
    })
    return openRequests.compactMap { request in
        guard request.$user.id != actorId,
              let requestId = request.id,
              let item = itemsById[request.$item.id],
              let itemId = item.id,
              let requester = usersById[request.$user.id],
              let requesterUserId = requester.id else {
            return nil
        }

        let candidateEntries = myEntries.filter { entry in
            guard let entryItem = itemsById[entry.$item.id] else { return false }
            return itemSearchItemsMatch(requestItem: item, entryItem: entryItem) &&
                itemSearchNotesMatch(requestNote: request.note, entryNote: entry.note)
        }.sorted { left, right in
            let leftEnough = left.qty >= request.qty ? 1 : 0
            let rightEnough = right.qty >= request.qty ? 1 : 0
            if leftEnough != rightEnough { return leftEnough > rightEnough }
            if left.qty != right.qty { return left.qty > right.qty }
            let leftTime = left.createdAt?.timeIntervalSince1970 ?? 0
            let rightTime = right.createdAt?.timeIntervalSince1970 ?? 0
            return leftTime > rightTime
        }
        guard let entry = candidateEntries.first,
              let matchedItem = itemsById[entry.$item.id],
              let matchedItemId = matchedItem.id,
              let entryId = entry.id,
              let entryOwner = usersById[entry.$user.id],
              let entryOwnerUserId = entryOwner.id else {
            return nil
        }

        return .init(
            requestId: requestId,
            itemId: itemId,
            matchedItemId: matchedItemId,
            itemName: item.name,
            requesterUserId: requesterUserId,
            requesterUsername: requester.username,
            entryId: entryId,
            entryOwnerUserId: entryOwnerUserId,
            entryOwnerUsername: entryOwner.username,
            locationId: entry.$location.id,
            locationLabel: buildItemSearchLocationLabel(locationId: entry.$location.id, byId: locationsById),
            requestedQty: request.qty,
            availableQty: entry.qty,
            averageQuality: request.averageQuality,
            note: request.note,
            hasEnoughQty: entry.qty >= request.qty,
            createdAt: request.createdAt
        )
    }.sorted {
        let leftEnough = $0.hasEnoughQty ? 1 : 0
        let rightEnough = $1.hasEnoughQty ? 1 : 0
        if leftEnough != rightEnough { return leftEnough > rightEnough }
        let leftTime = $0.createdAt?.timeIntervalSince1970 ?? 0
        let rightTime = $1.createdAt?.timeIntervalSince1970 ?? 0
        return leftTime > rightTime
    }
}

func createItemSearchOffer(_ req: Request) async throws -> ItemSearchDetailResponseDTO {
    let actor = try requireItemSearchUser(req)
    guard let requestModel = try await ItemSearchRequest.find(req.parameters.get("requestID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let requestId = try requestModel.requireID()
    let actorId = try actor.requireID()

    if requestModel.$user.id == actor.id {
        throw Abort(.forbidden, reason: "You may not offer on your own search request")
    }

    let existingOffer = try await ItemSearchOffer.query(on: req.db)
        .filter(\.$request.$id == requestId)
        .filter(\.$user.$id == actorId)
        .first()

    let body = try req.content.decode(ItemSearchOfferCreateDTO.self)
    let sanitizedNote = sanitizeItemSearchText(body.note, maxLength: 1000)

    if let existingOffer {
        if body.note != nil {
            existingOffer.note = sanitizedNote
        }
        if let hasResources = body.hasResources {
            existingOffer.hasResources = hasResources
        }
        try await existingOffer.save(on: req.db)

        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "item-search.offer.update",
            entityType: "item_search_offer",
            entityId: existingOffer.id,
            details: "requestId=\(requestId.uuidString)"
        )
    } else {
        let offer = ItemSearchOffer(
            requestID: requestId,
            userID: actorId,
            note: sanitizedNote,
            hasResources: body.hasResources ?? false
        )
        try await offer.save(on: req.db)

        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "item-search.offer.create",
            entityType: "item_search_offer",
            entityId: offer.id,
            details: "requestId=\(requestId.uuidString)"
        )
    }

    return try await getItemSearchItemById(requestModel.$item.id, on: req.db)
}

func updateItemSearchRequestStatus(_ req: Request) async throws -> ItemSearchDetailResponseDTO {
    let actor = try requireItemSearchUser(req)
    guard let requestModel = try await ItemSearchRequest.find(req.parameters.get("requestID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard canManageItemSearchRequest(actor, request: requestModel) else {
        throw Abort(.forbidden, reason: "You may not manage this search request")
    }

    let body = try req.content.decode(ItemSearchRequestStatusUpdateDTO.self)
    requestModel.status = body.status
    try await requestModel.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "item-search.request.status",
        entityType: "item_search_request",
        entityId: requestModel.id,
        details: "status=\(body.status.rawValue)"
    )

    return try await getItemSearchItemById(requestModel.$item.id, on: req.db)
}

func updateItemSearchRequestResources(_ req: Request) async throws -> ItemSearchDetailResponseDTO {
    let actor = try requireItemSearchUser(req)
    guard let requestModel = try await ItemSearchRequest.find(req.parameters.get("requestID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard canManageItemSearchRequest(actor, request: requestModel) else {
        throw Abort(.forbidden, reason: "You may not manage this search request")
    }

    let body = try req.content.decode(ItemSearchRequestResourcesUpdateDTO.self)
    requestModel.hasResources = body.hasResources
    try await requestModel.save(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "item-search.request.resources",
        entityType: "item_search_request",
        entityId: requestModel.id,
        details: "hasResources=\(body.hasResources)"
    )

    return try await getItemSearchItemById(requestModel.$item.id, on: req.db)
}

func deleteItemSearchRequest(_ req: Request) async throws -> ItemSearchDetailResponseDTO {
    let actor = try requireItemSearchUser(req)
    guard let requestModel = try await ItemSearchRequest.find(req.parameters.get("requestID"), on: req.db) else {
        throw Abort(.notFound)
    }
    guard canManageItemSearchRequest(actor, request: requestModel) else {
        throw Abort(.forbidden, reason: "You may not delete this search request")
    }

    let itemId = requestModel.$item.id
    let requestId = requestModel.id
    try await requestModel.delete(on: req.db)

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "item-search.request.delete",
        entityType: "item_search_request",
        entityId: requestId
    )

    return try await getItemSearchItemById(itemId, on: req.db)
}

func fulfillItemSearchRequestFromEntry(_ req: Request) async throws -> [InventoryMatchResponseDTO] {
    let actor = try requireItemSearchUser(req)
    let actorId = try actor.requireID()
    guard let requestModel = try await ItemSearchRequest.find(req.parameters.get("requestID"), on: req.db) else {
        throw Abort(.notFound)
    }
    let body = try req.content.decode(FulfillItemSearchRequestFromEntryDTO.self)
    guard let entry = try await StorageEntry.find(body.entryId, on: req.db) else {
        throw Abort(.notFound, reason: "Storage entry not found")
    }

    guard entry.$user.id == actorId || actor.role == .admin || actor.role == .superAdmin else {
        throw Abort(.forbidden, reason: "You may only fulfill requests from your own storage entries")
    }
    guard requestModel.status == .open else {
        throw Abort(.badRequest, reason: "Request is not open")
    }
    guard requestModel.$item.id == entry.$item.id else {
        throw Abort(.badRequest, reason: "Storage entry does not match requested item")
    }
    guard requestModel.$user.id != actorId else {
        throw Abort(.badRequest, reason: "You may not fulfill your own request from this flow")
    }
    guard entry.qty >= requestModel.qty else {
        throw Abort(.badRequest, reason: "Storage entry does not contain enough quantity")
    }

    let requestId = try requestModel.requireID()
    let itemId = requestModel.$item.id
    let entryId = try entry.requireID()
    let requestedQty = requestModel.qty

    try await req.db.transaction { database in
        if entry.qty == requestedQty {
            try await entry.delete(on: database)
        } else {
            entry.qty -= requestedQty
            try await entry.save(on: database)
        }
        try await requestModel.delete(on: database)
    }

    await recordAuditEvent(
        on: req,
        actor: actor,
        action: "item-search.request.fulfill-from-entry",
        entityType: "item_search_request",
        entityId: requestId,
        details: "entryId=\(entryId.uuidString);itemId=\(itemId.uuidString);qty=\(requestedQty)"
    )

    return try await listMyInventoryMatches(req)
}

private func getItemSearchItemById(_ itemId: UUID?, on db: Database) async throws -> ItemSearchDetailResponseDTO {
    guard let itemId,
          let item = try await Blueprint.find(itemId, on: db) else {
        throw Abort(.notFound)
    }

    let items = try await Blueprint.query(on: db)
        .filter(\.$category == .blueprints)
        .all()
    let requests = try await ItemSearchRequest.query(on: db)
        .all()
    let requestIds = requests.compactMap(\.id)
    let offers = requestIds.isEmpty ? [] : try await ItemSearchOffer.query(on: db)
        .filter(\.$request.$id ~~ requestIds)
        .all()
    let users = try await User.query(on: db).all()

    let usersById = Dictionary(uniqueKeysWithValues: users.compactMap { user in
        user.id.map { ($0, user) }
    })
    let itemsById = Dictionary(uniqueKeysWithValues: items.compactMap { blueprint in
        blueprint.id.map { ($0, blueprint) }
    })
    let grouped = Dictionary(grouping: items, by: { $0.$parent.id })
    let offerMap = buildItemSearchOfferMap(offers: offers, usersById: usersById)
    let requestsByItem = buildItemSearchRequestMap(requests: requests, usersById: usersById, offerMap: offerMap)
    let requestDtos = requestsByItem[itemId] ?? []

    var breadcrumbIds: [UUID] = []
    var currentParentId = item.$parent.id
    while let parentId = currentParentId, let parent = itemsById[parentId] {
        breadcrumbIds.insert(parentId, at: 0)
        currentParentId = parent.$parent.id
    }

    let breadcrumb = breadcrumbIds.compactMap { id in
        itemsById[id].map { ItemSearchBreadcrumbItemDTO(id: id, name: $0.name) }
    } + [ItemSearchBreadcrumbItemDTO(id: itemId, name: item.name)]

    let children = try (grouped[itemId] ?? [])
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .map { child in
            guard let childId = child.id else { throw Abort(.internalServerError) }
            let childRequests = requestsByItem[childId] ?? []
            let childOffersCount = childRequests.reduce(0) { $0 + $1.offers.count }
            return ItemSearchChildSummaryDTO(
                id: childId,
                name: child.name,
                itemCode: child.itemCode,
                badges: decodeItemSearchBadges(child.badgesCSV),
                openRequestCount: childRequests.filter { $0.status == .open }.count,
                offerCount: childOffersCount
            )
        }

    return .init(
        id: itemId,
        parentId: item.$parent.id,
        name: item.name,
        description: item.description,
        itemCode: item.itemCode,
        badges: decodeItemSearchBadges(item.badgesCSV),
        availableBadges: collectItemSearchBadges(items),
        breadcrumb: breadcrumb,
        children: children,
        requests: requestDtos
    )
}
