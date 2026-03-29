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
                averageQuality: request.averageQuality,
                note: request.note,
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
    if existingOffer != nil {
        throw Abort(.badRequest, reason: "You already offered help for this request")
    }

    let body = try req.content.decode(ItemSearchOfferCreateDTO.self)
    let offer = ItemSearchOffer(
        requestID: requestId,
        userID: actorId,
        note: sanitizeItemSearchText(body.note, maxLength: 1000)
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
