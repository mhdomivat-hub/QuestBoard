import Vapor
import Fluent
import Foundation
import FoundationNetworking

private struct SCMDBVersionsEntry: Content {
    let version: String
    let file: String
}

private struct SCMDBCraftingBlueprintsPayload: Codable {
    let version: String
    let blueprints: [SCMDBCraftingBlueprint]
}

private struct SCMDBCraftingBlueprint: Codable {
    let guid: String
    let tag: String
    let productEntityClass: String?
    let type: String?
    let subtype: String?
    let tiers: [SCMDBCraftingTier]
    let productName: String?
}

private struct SCMDBCraftingTier: Codable {
    let slots: [SCMDBCraftingSlot]
}

private struct SCMDBCraftingSlot: Codable {
    let name: String?
    let options: [SCMDBCraftingOption]
}

private struct SCMDBCraftingOption: Codable {
    let type: String
    let quantity: Double?
    let minQuality: Int?
    let resourceName: String?
    let itemName: String?
}

private struct SCMDBCraftingItemsPayload: Codable {
    let items: [SCMDBCraftingItem]
}

private struct SCMDBCraftingItem: Codable {
    let entityClass: String
    let itemType: String?
    let attachType: String?
    let attachSubType: String?
    let manufacturer: String?
    let manufacturerCode: String?
    let componentClass: String?
    let grade: Int?
    let name: String?
}

private struct SCMDBLocalSnapshot: Codable {
    let sourceBaseURL: String
    let version: String
    let fetchedAt: String
    let craftingBlueprints: SCMDBCraftingBlueprintsPayload
    let craftingItems: SCMDBCraftingItemsPayload
}

private struct SCMDBArmorGrouping {
    let className: String
    let family: String
    let variant: String?
    let slotName: String?
}

private struct SCMDBWeaponGrouping {
    let baseName: String
    let variantName: String?
}

private struct SCMDBImportEntry {
    let section: String
    let path: [String]
    let itemName: String
    let itemCode: String?
    let badges: [String]
    let resources: [SCMDBRecipeResourceEntry]
}

private struct SCMDBResourceEntry {
    let name: String
    let group: String
}

private struct SCMDBRecipeResourceEntry {
    let slotName: String
    let resourceName: String
    let quantity: Double
    let minQuality: Int?
}

private let defaultSCMDBBaseURL = "https://scmdb.net"
private let scmdbSectionCrafting = "Crafting"
private let scmdbSectionFPS = "FPS"
private let scmdbSectionVehicle = "Vehicle"
private let scmdbSectionWeapons = "Waffen"
private let scmdbSectionVehicleComponents = "Komponenten"
private let scmdbSectionArmor = "Ruestungen"
private let scmdbSectionOtherCrafting = "Sonstiges"
private let scmdbSectionResources = "Ressourcen"
private let scmdbSectionHandminable = "Handminable"
private let scmdbSectionShipminable = "Shipminable"
private let scmdbImportBadge = "SCMDB"
private let localSCMDBSnapshotPath = "/app/SCMDBSnapshot/scmdb-fabricator-snapshot.json"
private let scmdbVehicleComponentTypes: Set<String> = [
    "cooler",
    "mininglaser",
    "powerplant",
    "quantumdrive",
    "radar",
    "refuelling",
    "salvage",
    "shield",
    "tractorbeam"
]

private func normalizeSCMDBBaseURL(_ raw: String?) throws -> String {
    let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !value.isEmpty else { return defaultSCMDBBaseURL }

    guard let components = URLComponents(string: value),
          let scheme = components.scheme,
          let host = components.host,
          ["http", "https"].contains(scheme.lowercased()) else {
        throw Abort(.badRequest, reason: "Ungueltige SCMDB-URL")
    }

    var normalized = "\(scheme)://\(host)"
    if let port = components.port {
        normalized += ":\(port)"
    }
    return normalized
}

private func fetchRemoteData(from urlString: String, req: Request, context: String) async throws -> Data {
    guard let url = URL(string: urlString) else {
        throw Abort(.badRequest, reason: "\(context) URL ist ungueltig")
    }

    do {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            req.logger.error("\(context) returned empty body")
            throw Abort(.badGateway, reason: "\(context) lieferte keine Daten")
        }
        return data
    } catch let abort as Abort {
        throw abort
    } catch {
        req.logger.error("\(context) request failed: \(error.localizedDescription)")
        throw Abort(.badGateway, reason: "\(context) konnte nicht geladen werden")
    }
}

private func decodeRemoteJSON<T: Decodable>(_ type: T.Type, from data: Data, req: Request, context: String) async throws -> T {
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        req.logger.error("\(context) decode failed: \(error.localizedDescription)")
        throw Abort(.badGateway, reason: "\(context) konnte nicht decodiert werden")
    }
}

private func dataByRemovingUTF8BOM(_ data: Data) -> Data {
    let bom = Data([0xEF, 0xBB, 0xBF])
    guard data.starts(with: bom) else { return data }
    return Data(data.dropFirst(bom.count))
}

private func writeSCMDBSnapshot(version: String, sourceBaseURL: String, craftingBlueprints: SCMDBCraftingBlueprintsPayload, craftingItems: SCMDBCraftingItemsPayload, req: Request) -> Bool {
    let snapshot = SCMDBLocalSnapshot(
        sourceBaseURL: sourceBaseURL,
        version: version,
        fetchedAt: ISO8601DateFormatter().string(from: Date()),
        craftingBlueprints: craftingBlueprints,
        craftingItems: craftingItems
    )

    do {
        let url = URL(fileURLWithPath: localSCMDBSnapshotPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
        return true
    } catch {
        req.logger.warning("SCMDB snapshot write failed: \(error.localizedDescription)")
        return false
    }
}

private func loadSCMDBSourceData(req: Request, sourceBaseURL: String, sourceMode: String?, updateSnapshot: Bool) async throws -> (version: String, craftingBlueprints: SCMDBCraftingBlueprintsPayload, craftingItems: SCMDBCraftingItemsPayload, sourceLabel: String, snapshotUpdated: Bool) {
    let normalizedMode = sourceMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let preferLive = normalizedMode == "live"

    if !preferLive && FileManager.default.fileExists(atPath: localSCMDBSnapshotPath) {
        do {
            let snapshotData = try Data(contentsOf: URL(fileURLWithPath: localSCMDBSnapshotPath))
            let snapshot = try JSONDecoder().decode(SCMDBLocalSnapshot.self, from: dataByRemovingUTF8BOM(snapshotData))
            req.logger.info("Using local SCMDB snapshot at \(localSCMDBSnapshotPath)")
            return (snapshot.version, snapshot.craftingBlueprints, snapshot.craftingItems, "snapshot", false)
        } catch {
            req.logger.warning("Local SCMDB snapshot unreadable, falling back to live source: \(error.localizedDescription)")
        }
    }

    let versionsData = try await fetchRemoteData(from: "\(sourceBaseURL)/data/versions.json", req: req, context: "SCMDB versions")
    let versions = try await decodeRemoteJSON([SCMDBVersionsEntry].self, from: versionsData, req: req, context: "SCMDB versions")
    guard let selectedVersion = versions.first else {
        throw Abort(.badGateway, reason: "SCMDB lieferte keine Versionen")
    }

    let craftingBlueprintsData = try await fetchRemoteData(
        from: "\(sourceBaseURL)/data/crafting_blueprints-\(selectedVersion.version).json",
        req: req,
        context: "SCMDB crafting blueprints"
    )
    let craftingItemsData = try await fetchRemoteData(
        from: "\(sourceBaseURL)/data/crafting_items-\(selectedVersion.version).json",
        req: req,
        context: "SCMDB crafting items"
    )

    let craftingBlueprintsPayload = try await decodeRemoteJSON(
        SCMDBCraftingBlueprintsPayload.self,
        from: craftingBlueprintsData,
        req: req,
        context: "SCMDB crafting blueprints"
    )
    let craftingItemsPayload = try await decodeRemoteJSON(
        SCMDBCraftingItemsPayload.self,
        from: craftingItemsData,
        req: req,
        context: "SCMDB crafting items"
    )

    let snapshotUpdated = updateSnapshot ? writeSCMDBSnapshot(version: selectedVersion.version, sourceBaseURL: sourceBaseURL, craftingBlueprints: craftingBlueprintsPayload, craftingItems: craftingItemsPayload, req: req) : false

    return (selectedVersion.version, craftingBlueprintsPayload, craftingItemsPayload, "live", snapshotUpdated)
}

private func scmdbLookupKey(parentId: UUID?, name: String) -> String {
    let normalizedName = name
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return "\(parentId?.uuidString ?? "root")|\(normalizedName)"
}

private func sanitizeSCMDBBadges(_ badges: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []

    for raw in badges {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let normalized = String(trimmed.prefix(32))
        let key = normalized.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(normalized)
    }

    return result
}

private func decodeSCMDBBadges(_ raw: String?) -> [String] {
    guard let raw, !raw.isEmpty else { return [] }
    return raw
        .split(separator: ",")
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func encodeSCMDBBadges(_ badges: [String]) -> String? {
    let sanitized = sanitizeSCMDBBadges(badges)
    guard !sanitized.isEmpty else { return nil }
    return sanitized.joined(separator: ",")
}

private func badgeDefinitionGroup(for badge: String) -> String? {
    switch badge {
    case scmdbImportBadge:
        return "Quelle"
    case scmdbSectionCrafting, scmdbSectionResources, scmdbSectionVehicle:
        return "Import"
    case scmdbSectionFPS:
        return "Import"
    case scmdbSectionHandminable, scmdbSectionShipminable:
        return "Ressourcenart"
    case "Waffe", "Ruestung", scmdbSectionVehicleComponents, scmdbSectionOtherCrafting:
        return "Kategorie"
    case "Leicht", "Mittel", "Schwer", "Backpacks", "Flight Suits":
        return "Ruestungsklasse"
    default:
        if badge.hasPrefix("Size ") { return "Size" }
        if badge.hasPrefix("Grade ") { return "Grade" }
        if badge.hasPrefix("Slot: ") { return "Slot" }
        if badge.hasPrefix("Klasse: ") { return "Komponentenklasse" }
        return "Untergruppe"
    }
}

private let legacySCMDBDescriptions: Set<String> = [
    "Importierte Crafting-Items aus SCMDB",
    "Craftbare Waffen aus SCMDB",
    "Craftbare Ruestungen aus SCMDB",
    "Weitere craftbare Items aus SCMDB",
    "Ressourcen aus SCMDB",
    "Handabbaubare Ressourcen aus SCMDB",
    "Schiffsabbaubare Ressourcen aus SCMDB"
]

private func ensureBadgeDefinitionsExist(
    badges: [String],
    existingDefinitions: inout [String: ItemBadgeDefinition],
    on db: Database
) async throws {
    for badge in sanitizeSCMDBBadges(badges) {
        let key = badge.lowercased()
        let targetGroup = badgeDefinitionGroup(for: badge)
        if let existing = existingDefinitions[key] {
            if existing.groupName == nil, let targetGroup {
                existing.groupName = targetGroup
                try await existing.save(on: db)
            }
            continue
        }

        let definition = ItemBadgeDefinition(name: badge, groupName: targetGroup)
        try await definition.save(on: db)
        existingDefinitions[key] = definition
    }
}

private func titleCase(_ raw: String) -> String {
    raw
        .split(separator: "_")
        .map { fragment in
            fragment.prefix(1).uppercased() + fragment.dropFirst().lowercased()
        }
        .joined(separator: " ")
}

private func weaponSubtypeLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case "lmg": return "LMG"
    case "smg": return "SMG"
    case "sniper": return "Sniper"
    case "shotgun": return "Shotgun"
    case "pistol": return "Pistole"
    case "rifle": return "Rifle"
    case "launcher": return "Launcher"
    case "multitool": return "Multitool"
    case "knife": return "Messer"
    case "utility": return "Utility"
    case "ballistic": return "Ballistisch"
    case "laser": return "Laser"
    default: return titleCase(raw)
    }
}

private func vehicleSizeLabel(_ raw: String?) -> String {
    let normalized = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.hasPrefix("size") {
        let suffix = normalized.dropFirst(4)
        return suffix.isEmpty ? "Size unbekannt" : "Size \(suffix)"
    }

    switch normalized {
    case "small": return "Small"
    case "medium": return "Medium"
    case "large": return "Large"
    default: return "Ohne Size"
    }
}

private func vehicleComponentTypeLabel(_ raw: String) -> String {
    switch raw.lowercased() {
    case "cooler": return "Cooler"
    case "mininglaser": return "Mining Laser"
    case "powerplant": return "Power Plant"
    case "quantumdrive": return "Quantum Drive"
    case "radar": return "Radar"
    case "refuelling": return "Refuelling"
    case "salvage": return "Salvage"
    case "shield": return "Shield"
    case "tractorbeam": return "Tractor Beam"
    default: return titleCase(raw)
    }
}

private func vehicleComponentClassLabel(item: SCMDBCraftingItem?, tag: String) -> String {
    let itemClass = (item?.componentClass ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !itemClass.isEmpty {
        return titleCase(itemClass)
    }

    let pattern = #"(?:^|_)(Civilian|Military|Industrial|Competition|Stealth|Utility)(?:_|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
          let range = Range(match.range(at: 1), in: tag) else {
        return "Unbekannt"
    }

    switch tag[range].lowercased() {
    case "civilian": return "Civilian"
    case "military": return "Military"
    case "industrial": return "Industrial"
    case "competition": return "Competition"
    case "stealth": return "Stealth"
    case "utility": return "Utility"
    default: return titleCase(String(tag[range]))
    }
}

private func vehicleComponentGradeLabel(item: SCMDBCraftingItem?) -> String {
    guard let grade = item?.grade else { return "Grade unbekannt" }
    return "Grade \(grade)"
}

private func vehicleWeaponSizeLabel(tag: String, productName: String) -> String {
    for pattern in [#"_S(\d+)(?:_|$)"#, #"\(S(\d+)\)"#] {
        let source = pattern.contains("_S") ? tag : productName
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let range = Range(match.range(at: 1), in: source) else {
            continue
        }
        return "Size \(source[range])"
    }

    return "Size unbekannt"
}

private func vehicleWeaponKindLabel(tag: String, productName: String) -> String {
    let combined = "\(tag) \(productName)"
    let checks: [(String, String)] = [
        ("MassDriver", "Mass Driver"),
        ("ScatterGun", "Scattergun"),
        ("Scattergun", "Scattergun"),
        ("Gatling", "Gatling"),
        ("Repeater", "Repeater"),
        ("Cannon", "Cannon")
    ]

    for (needle, label) in checks where combined.range(of: needle, options: .caseInsensitive) != nil {
        return label
    }

    return "Sonstiges"
}

private func normalizeWeaponGrouping(productName: String) -> SCMDBWeaponGrouping {
    let trimmed = productName.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = #""([^"]+)""#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let variantRange = Range(match.range(at: 1), in: trimmed),
          let fullMatchRange = Range(match.range(at: 0), in: trimmed) else {
        return .init(baseName: trimmed, variantName: nil)
    }

    let variantName = String(trimmed[variantRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    var baseName = trimmed.replacingCharacters(in: fullMatchRange, with: "")
    baseName = baseName.replacingOccurrences(of: "  ", with: " ")
    baseName = baseName.trimmingCharacters(in: .whitespacesAndNewlines)

    return .init(
        baseName: baseName.isEmpty ? trimmed : baseName,
        variantName: variantName.isEmpty ? nil : variantName
    )
}

private func armorClassLabel(raw: String?, attachType: String?, blueprintSubtype: String?) -> String {
    if attachType == "Char_Armor_Backpack" {
        return "Backpacks"
    }
    if blueprintSubtype?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "flightsuit" {
        return "Flight Suits"
    }

    switch raw?.lowercased() {
    case "light", "lightarmor":
        return "Leicht"
    case "medium":
        return "Mittel"
    case "heavy":
        return "Schwer"
    default:
        return "Unbekannt"
    }
}

private func armorSlotLabel(_ raw: String?) -> String? {
    switch raw {
    case "Char_Armor_Helmet": return "Helm"
    case "Char_Armor_Torso": return "Torso"
    case "Char_Armor_Arms": return "Arme"
    case "Char_Armor_Legs": return "Beine"
    case "Char_Armor_Backpack": return "Rucksack"
    case "Char_Armor_Undersuit": return "Undersuit"
    default: return nil
    }
}

private func splitWords(_ value: String) -> [String] {
    value.split(separator: " ").map(String.init)
}

private func scmdbDisplayName(blueprint: SCMDBCraftingBlueprint, item: SCMDBCraftingItem?) -> String {
    let productName = (blueprint.productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !productName.isEmpty { return productName }

    let itemName = (item?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !itemName.isEmpty { return itemName }

    return blueprint.tag
}

private func normalizeArmorGrouping(productName: String, item: SCMDBCraftingItem?, blueprintSubtype: String?) -> SCMDBArmorGrouping {
    let slotLabel = armorSlotLabel(item?.attachType)
    let className = armorClassLabel(raw: item?.attachSubType, attachType: item?.attachType, blueprintSubtype: blueprintSubtype)

    let tokens = splitWords(productName)
    let slotIndex = slotLabel == nil ? nil : tokens.firstIndex(where: { token in
        switch token.lowercased() {
        case "helmet", "core", "arms", "legs", "backpack", "undersuit", "torso":
            return true
        default:
            return false
        }
    })

    let prefixTokens = slotIndex.map { Array(tokens[..<$0]) } ?? tokens
    let suffixTokens = slotIndex.map { Array(tokens[($0 + 1)...]) } ?? []

    var family = prefixTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if family.isEmpty {
        family = prefixTokens.first ?? productName
    }

    let variant = suffixTokens.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return .init(
        className: className,
        family: family,
        variant: variant.isEmpty ? nil : variant,
        slotName: slotLabel
    )
}

private func buildCraftingEntries(
    blueprints: [SCMDBCraftingBlueprint],
    itemMapByEntityClass: [String: SCMDBCraftingItem]
) -> [SCMDBImportEntry] {
    blueprints.map { blueprint in
        let item = blueprint.productEntityClass.flatMap { itemMapByEntityClass[$0] }
        let blueprintType = blueprint.type ?? ""
        let blueprintSubtype = blueprint.subtype ?? ""
        let displayName = scmdbDisplayName(blueprint: blueprint, item: item)
        let recipeResources = collectRecipeResources(from: blueprint)

        if blueprintType.lowercased() == "armour" {
            let grouping = normalizeArmorGrouping(productName: displayName, item: item, blueprintSubtype: blueprintSubtype)
            var path = [scmdbSectionCrafting, scmdbSectionFPS, scmdbSectionArmor, grouping.className, grouping.family]
            if let variant = grouping.variant {
                path.append(variant)
            }

            var badges = [
                scmdbImportBadge,
                scmdbSectionCrafting,
                "Ruestung",
                grouping.className
            ]
            if let slotName = grouping.slotName {
                badges.append("Slot: \(slotName)")
            }

            return .init(
                section: scmdbSectionArmor,
                path: path,
                itemName: displayName,
                itemCode: blueprint.tag,
                badges: badges,
                resources: recipeResources
            )
        }

        if blueprintType.lowercased() == "weapons",
           item?.attachType == "WeaponGun" {
            let weaponType = weaponSubtypeLabel(blueprintSubtype)
            let size = vehicleWeaponSizeLabel(tag: blueprint.tag, productName: displayName)
            let weaponKind = vehicleWeaponKindLabel(tag: blueprint.tag, productName: displayName)

            return .init(
                section: "\(scmdbSectionVehicle) / \(scmdbSectionWeapons)",
                path: [scmdbSectionCrafting, scmdbSectionVehicle, scmdbSectionWeapons, weaponType, size, weaponKind],
                itemName: displayName,
                itemCode: blueprint.tag,
                badges: [
                    scmdbImportBadge,
                    scmdbSectionVehicle,
                    "Waffe",
                    weaponType,
                    size,
                    weaponKind
                ],
                resources: recipeResources
            )
        }

        if blueprintType.lowercased() == "weapons" {
            let subtype = weaponSubtypeLabel(blueprintSubtype)
            let grouping = normalizeWeaponGrouping(productName: displayName)
            var path = [scmdbSectionCrafting, scmdbSectionFPS, scmdbSectionWeapons, subtype]
            if grouping.variantName != nil {
                path.append(grouping.baseName)
            }

            var badges = [
                scmdbImportBadge,
                scmdbSectionCrafting,
                "Waffe",
                subtype
            ]
            if grouping.variantName != nil {
                badges.append("Skin")
            }

            return .init(
                section: scmdbSectionWeapons,
                path: path,
                itemName: grouping.variantName ?? grouping.baseName,
                itemCode: blueprint.tag,
                badges: badges,
                resources: recipeResources
            )
        }

        if scmdbVehicleComponentTypes.contains(blueprintType.lowercased()) {
            let size = vehicleSizeLabel(blueprintSubtype)
            let typeLabel = vehicleComponentTypeLabel(blueprintType)
            let classLabel = vehicleComponentClassLabel(item: item, tag: blueprint.tag)
            let gradeLabel = vehicleComponentGradeLabel(item: item)

            return .init(
                section: "\(scmdbSectionVehicle) / \(scmdbSectionVehicleComponents)",
                path: [scmdbSectionCrafting, scmdbSectionVehicle, scmdbSectionVehicleComponents, size, typeLabel, classLabel, gradeLabel],
                itemName: displayName,
                itemCode: blueprint.tag,
                badges: [
                    scmdbImportBadge,
                    scmdbSectionVehicle,
                    scmdbSectionVehicleComponents,
                    size,
                    typeLabel,
                    "Klasse: \(classLabel)",
                    gradeLabel
                ],
                resources: recipeResources
            )
        }

        let typeLabel = blueprintType.isEmpty ? scmdbSectionOtherCrafting : titleCase(blueprintType)
        return .init(
            section: scmdbSectionOtherCrafting,
            path: [scmdbSectionCrafting, scmdbSectionFPS, scmdbSectionOtherCrafting, typeLabel],
            itemName: displayName,
            itemCode: blueprint.tag,
            badges: [
                scmdbImportBadge,
                scmdbSectionCrafting,
                scmdbSectionOtherCrafting,
                typeLabel
            ],
            resources: recipeResources
        )
    }
}

private func collectRecipeResources(from blueprint: SCMDBCraftingBlueprint) -> [SCMDBRecipeResourceEntry] {
    var result: [SCMDBRecipeResourceEntry] = []
    for tier in blueprint.tiers {
        for slot in tier.slots {
            let slotName = slot.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            for option in slot.options {
                let optionType = option.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let materialName: String?
                if optionType == "resource" {
                    materialName = option.resourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if optionType == "item" {
                    materialName = option.itemName?.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    materialName = nil
                }

                guard let materialName, !materialName.isEmpty else {
                    continue
                }

                result.append(.init(
                    slotName: slotName?.isEmpty == false ? slotName! : "Material",
                    resourceName: materialName,
                    quantity: option.quantity ?? 0,
                    minQuality: option.minQuality
                ))
            }
        }
    }
    return result
}

private func collectCraftingResources(from blueprints: [SCMDBCraftingBlueprint]) -> [SCMDBResourceEntry] {
    var resourceGroups: [String: String] = [:]
    for blueprint in blueprints {
        for tier in blueprint.tiers {
            for slot in tier.slots {
                for option in slot.options {
                    let type = option.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if type == "resource" {
                        let name = (option.resourceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            resourceGroups[name] = scmdbSectionShipminable
                        }
                    } else if type == "item" {
                        let name = (option.itemName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            resourceGroups[name] = scmdbSectionHandminable
                        }
                    }
                }
            }
        }
    }

    return resourceGroups.keys
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        .map { name in
            SCMDBResourceEntry(name: name, group: resourceGroups[name] ?? scmdbSectionShipminable)
        }
}

private func deleteLegacySCMDBResourceChildren(resourcesSectionId: UUID, req: Request) async throws {
    let resourceChildren = try await Blueprint.query(on: req.db)
        .filter(\.$parent.$id == resourcesSectionId)
        .all()

    for child in resourceChildren {
        let badges = decodeSCMDBBadges(child.badgesCSV)
        guard badges.contains(scmdbImportBadge) else { continue }
        if child.name == scmdbSectionHandminable || child.name == scmdbSectionShipminable {
            continue
        }
        try await child.delete(on: req.db)
    }
}

private func ensureSCMDBNode(
    parentId: UUID?,
    name: String,
    description: String?,
    itemCode: String?,
    badges: [String],
    items: inout [Blueprint],
    index: inout [String: Blueprint],
    dryRun: Bool,
    db: Database
) async throws -> (item: Blueprint, created: Bool) {
    let lookupKey = scmdbLookupKey(parentId: parentId, name: name)
    let encodedBadges = encodeSCMDBBadges(badges)

    if let existing = index[lookupKey] {
        if !dryRun {
            var changed = false
            let mergedBadges = encodeSCMDBBadges(decodeSCMDBBadges(existing.badgesCSV) + badges)
            if existing.badgesCSV != mergedBadges {
                existing.badgesCSV = mergedBadges
                changed = true
            }
            if existing.itemCode == nil, let itemCode {
                existing.itemCode = itemCode
                changed = true
            }
            if let description {
                if existing.description != description {
                    existing.description = description
                    changed = true
                }
            } else if let currentDescription = existing.description, legacySCMDBDescriptions.contains(currentDescription) {
                existing.description = nil
                changed = true
            }
            if changed {
                try await existing.save(on: db)
            }
        }
        return (existing, false)
    }

    let created = Blueprint(
        id: dryRun ? UUID() : nil,
        parentID: parentId,
        name: name,
        description: description,
        itemCode: itemCode,
        badgesCSV: encodedBadges,
        hideFromBlueprints: false,
        category: .blueprints,
        isCraftable: false
    )

    if !dryRun {
        try await created.save(on: db)
    }
    items.append(created)
    index[lookupKey] = created
    return (created, true)
}

private func buildSCMDBItemCodeIndex(from items: [Blueprint]) -> [String: Blueprint] {
    var index: [String: Blueprint] = [:]
    for item in items {
        guard let itemCode = item.itemCode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !itemCode.isEmpty,
              decodeSCMDBBadges(item.badgesCSV).contains(scmdbImportBadge) else {
            continue
        }
        if index[itemCode] == nil {
            index[itemCode] = item
        }
    }
    return index
}

private func buildSCMDBLookupIndex(from items: [Blueprint]) -> [String: Blueprint] {
    var index: [String: Blueprint] = [:]
    for item in items {
        let key = scmdbLookupKey(parentId: item.$parent.id, name: item.name)
        if index[key] == nil {
            index[key] = item
        }
    }
    return index
}

private func buildSCMDBCraftingItemIndex(from items: [SCMDBCraftingItem]) -> [String: SCMDBCraftingItem] {
    var index: [String: SCMDBCraftingItem] = [:]
    for item in items where index[item.entityClass] == nil {
        index[item.entityClass] = item
    }
    return index
}

private func buildBadgeDefinitionIndex(from definitions: [ItemBadgeDefinition]) -> [String: ItemBadgeDefinition] {
    var index: [String: ItemBadgeDefinition] = [:]
    for definition in definitions {
        let key = definition.name.lowercased()
        if index[key] == nil {
            index[key] = definition
        }
    }
    return index
}

private func ensureSCMDBLeaf(
    parentId: UUID?,
    name: String,
    itemCode: String?,
    badges: [String],
    items: inout [Blueprint],
    index: inout [String: Blueprint],
    itemCodeIndex: inout [String: Blueprint],
    dryRun: Bool,
    db: Database
) async throws -> (item: Blueprint, created: Bool) {
    let lookupKey = scmdbLookupKey(parentId: parentId, name: name)
    let normalizedCode = itemCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    let encodedBadges = encodeSCMDBBadges(badges)

    let existingByCode = normalizedCode.flatMap { itemCodeIndex[$0] }
    let existing = existingByCode ?? index[lookupKey]

    if let existing {
        if !dryRun {
            var changed = false
            let oldLookupKey = scmdbLookupKey(parentId: existing.$parent.id, name: existing.name)

            if existing.$parent.id != parentId {
                existing.$parent.id = parentId
                changed = true
            }
            if existing.name != name {
                existing.name = name
                changed = true
            }
            if existing.itemCode != normalizedCode {
                existing.itemCode = normalizedCode
                changed = true
            }
            if existing.badgesCSV != encodedBadges {
                existing.badgesCSV = encodedBadges
                changed = true
            }
            if let currentDescription = existing.description, legacySCMDBDescriptions.contains(currentDescription) {
                existing.description = nil
                changed = true
            }
            if changed {
                try await existing.save(on: db)
                index.removeValue(forKey: oldLookupKey)
                index[lookupKey] = existing
                if let normalizedCode {
                    itemCodeIndex[normalizedCode] = existing
                }
            }
        }
        return (existing, false)
    }

    let created = Blueprint(
        id: dryRun ? UUID() : nil,
        parentID: parentId,
        name: name,
        description: nil,
        itemCode: normalizedCode,
        badgesCSV: encodedBadges,
        hideFromBlueprints: false,
        category: .blueprints,
        isCraftable: false
    )

    if !dryRun {
        try await created.save(on: db)
    }
    items.append(created)
    index[lookupKey] = created
    if let normalizedCode {
        itemCodeIndex[normalizedCode] = created
    }
    return (created, true)
}

private func rebuildSCMDBRecipeResources(
    recipesByBlueprintId: [UUID: [SCMDBRecipeResourceEntry]],
    resourcesByName: [String: Blueprint],
    db: Database
) async throws {
    guard !recipesByBlueprintId.isEmpty else { return }

    for (blueprintId, recipes) in recipesByBlueprintId {
        try await BlueprintRecipeResource.query(on: db)
            .filter(\.$blueprint.$id == blueprintId)
            .delete()

        for recipe in recipes {
            guard let resource = resourcesByName[recipe.resourceName.lowercased()],
                  let resourceId = resource.id else {
                continue
            }
            let storedRecipe = BlueprintRecipeResource(
                blueprintID: blueprintId,
                resourceID: resourceId,
                slotName: String(recipe.slotName.prefix(120)),
                resourceName: String(recipe.resourceName.prefix(120)),
                quantity: recipe.quantity,
                minQuality: recipe.minQuality
            )
            try await storedRecipe.save(on: db)
        }
    }
}

private func deleteEmptySCMDBContainerNodes(on db: Database) async throws {
    var changed = true
    while changed {
        changed = false

        let items = try await Blueprint.query(on: db)
            .filter(\.$category == .blueprints)
            .all()
        let entryItemIds = Set(try await StorageEntry.query(on: db).all().map { $0.$item.id })
        let parentIds = Set(items.compactMap { $0.$parent.id })

        for item in items {
            let badges = decodeSCMDBBadges(item.badgesCSV)
            guard let itemId = item.id,
                  item.itemCode == nil,
                  badges.contains(scmdbImportBadge),
                  !badges.contains("Ressource"),
                  !parentIds.contains(itemId),
                  !entryItemIds.contains(itemId) else {
                continue
            }
            try await item.delete(on: db)
            changed = true
        }
    }
}

private func deleteLegacySCMDBSections(req: Request) async throws {
    let legacyTopLevelNames: Set<String> = ["SCMDB Import", "Item Rewards"]
    let rootItems = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()

    for item in rootItems where item.$parent.id == nil && legacyTopLevelNames.contains(item.name) {
        try await item.delete(on: req.db)
    }
}

func importSCMDBItems(_ req: Request) async throws -> SCMDBImportResultDTO {
    let actor = try requireAdminOrSuperAdmin(req)
    let payload = try req.content.decode(SCMDBImportRequestDTO.self)
    let dryRun = payload.dryRun ?? false
    let sourceBaseURL = try normalizeSCMDBBaseURL(payload.sourceBaseURL)
    let updateSnapshot = payload.updateSnapshot ?? false
    let sourceData = try await loadSCMDBSourceData(req: req, sourceBaseURL: sourceBaseURL, sourceMode: payload.sourceMode, updateSnapshot: updateSnapshot)

    let itemMapByEntityClass = buildSCMDBCraftingItemIndex(from: sourceData.craftingItems.items)
    let craftingEntries = buildCraftingEntries(
        blueprints: sourceData.craftingBlueprints.blueprints,
        itemMapByEntityClass: itemMapByEntityClass
    )
    let resourceEntries = collectCraftingResources(from: sourceData.craftingBlueprints.blueprints)

    var allItems = try await Blueprint.query(on: req.db)
        .filter(\.$category == .blueprints)
        .all()
    var itemIndex = buildSCMDBLookupIndex(from: allItems)
    var itemCodeIndex = buildSCMDBItemCodeIndex(from: allItems)
    var badgeDefinitions = buildBadgeDefinitionIndex(from: try await ItemBadgeDefinition.query(on: req.db).all())

    var inserted = 0
    var skipped = 0

    if !dryRun {
        try await deleteLegacySCMDBSections(req: req)
        allItems = try await Blueprint.query(on: req.db)
            .filter(\.$category == .blueprints)
            .all()
        itemIndex = buildSCMDBLookupIndex(from: allItems)
        itemCodeIndex = buildSCMDBItemCodeIndex(from: allItems)
    }

    try await ensureBadgeDefinitionsExist(
        badges: [
            scmdbImportBadge,
            scmdbSectionCrafting,
            scmdbSectionFPS,
            scmdbSectionVehicle,
            scmdbSectionResources,
            scmdbSectionHandminable,
            scmdbSectionShipminable,
            "Waffe",
            scmdbSectionVehicleComponents,
            "Ruestung",
            scmdbSectionOtherCrafting,
            "Leicht",
            "Mittel",
            "Schwer"
        ],
        existingDefinitions: &badgeDefinitions,
        on: req.db
    )

    let craftingSection = try await ensureSCMDBNode(
        parentId: nil,
        name: scmdbSectionCrafting,
        description: nil,
        itemCode: nil,
        badges: [scmdbImportBadge, scmdbSectionCrafting],
        items: &allItems,
        index: &itemIndex,
        dryRun: dryRun,
        db: req.db
    )
    if craftingSection.created { inserted += 1 } else { skipped += 1 }
    guard let craftingSectionId = craftingSection.item.id else {
        throw Abort(.internalServerError, reason: "SCMDB crafting section has no id")
    }

    let fpsSection = try await ensureSCMDBNode(
        parentId: craftingSectionId,
        name: scmdbSectionFPS,
        description: nil,
        itemCode: nil,
        badges: [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionFPS],
        items: &allItems,
        index: &itemIndex,
        dryRun: dryRun,
        db: req.db
    )
    if fpsSection.created { inserted += 1 } else { skipped += 1 }
    guard let fpsSectionId = fpsSection.item.id else {
        throw Abort(.internalServerError, reason: "SCMDB FPS section has no id")
    }

    let vehicleSection = try await ensureSCMDBNode(
        parentId: craftingSectionId,
        name: scmdbSectionVehicle,
        description: nil,
        itemCode: nil,
        badges: [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionVehicle],
        items: &allItems,
        index: &itemIndex,
        dryRun: dryRun,
        db: req.db
    )
    if vehicleSection.created { inserted += 1 } else { skipped += 1 }
    guard let vehicleSectionId = vehicleSection.item.id else {
        throw Abort(.internalServerError, reason: "SCMDB vehicle section has no id")
    }

    let staticSections: [(name: String, parentId: UUID?, badges: [String], description: String)] = [
        (scmdbSectionWeapons, fpsSectionId, [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionFPS, "Waffe"], ""),
        (scmdbSectionArmor, fpsSectionId, [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionFPS, "Ruestung"], ""),
        (scmdbSectionOtherCrafting, fpsSectionId, [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionFPS, scmdbSectionOtherCrafting], ""),
        (scmdbSectionWeapons, vehicleSectionId, [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionVehicle, "Waffe"], ""),
        (scmdbSectionVehicleComponents, vehicleSectionId, [scmdbImportBadge, scmdbSectionCrafting, scmdbSectionVehicle, scmdbSectionVehicleComponents], ""),
        (scmdbSectionResources, nil, [scmdbImportBadge, scmdbSectionResources], "")
    ]

    for section in staticSections {
        try await ensureBadgeDefinitionsExist(badges: section.badges, existingDefinitions: &badgeDefinitions, on: req.db)
        let result = try await ensureSCMDBNode(
            parentId: section.parentId,
            name: section.name,
            description: section.description.isEmpty ? nil : section.description,
            itemCode: nil,
            badges: section.badges,
            items: &allItems,
            index: &itemIndex,
            dryRun: dryRun,
            db: req.db
        )
        if result.created { inserted += 1 } else { skipped += 1 }
    }

    var recipesByBlueprintId: [UUID: [SCMDBRecipeResourceEntry]] = [:]
    for entry in craftingEntries {
        var currentParentId = craftingSectionId
        var inheritedBadges = [scmdbImportBadge]
        for segment in entry.path {
            switch segment {
            case scmdbSectionCrafting:
                currentParentId = craftingSectionId
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [scmdbSectionCrafting])
                continue
            case scmdbSectionVehicle:
                currentParentId = vehicleSectionId
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [scmdbSectionVehicle])
                continue
            case scmdbSectionFPS:
                currentParentId = fpsSectionId
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [scmdbSectionFPS])
                continue
            default:
                break
            }

            if segment == scmdbSectionWeapons {
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + ["Waffe"])
            } else if segment == scmdbSectionVehicleComponents {
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [scmdbSectionVehicleComponents])
            } else if segment == scmdbSectionArmor {
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + ["Ruestung"])
            } else if segment == scmdbSectionOtherCrafting {
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [scmdbSectionOtherCrafting])
            } else if ["Leicht", "Mittel", "Schwer"].contains(segment) {
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [segment])
            } else if entry.badges.contains("Klasse: \(segment)") {
                inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + ["Klasse: \(segment)"])
            } else if !["Waffe", "Ruestung", scmdbSectionOtherCrafting].contains(segment) {
                if entry.badges.contains(segment) {
                    inheritedBadges = sanitizeSCMDBBadges(inheritedBadges + [segment])
                }
            }

            try await ensureBadgeDefinitionsExist(badges: inheritedBadges, existingDefinitions: &badgeDefinitions, on: req.db)
            let nodeResult = try await ensureSCMDBNode(
                parentId: currentParentId,
                name: segment,
                description: nil,
                itemCode: nil,
                badges: inheritedBadges,
                items: &allItems,
                index: &itemIndex,
                dryRun: dryRun,
                db: req.db
            )
            if nodeResult.created { inserted += 1 } else { skipped += 1 }
            guard let nextParentId = nodeResult.item.id else {
                throw Abort(.internalServerError, reason: "SCMDB node '\(segment)' has no id")
            }
            currentParentId = nextParentId
        }

        try await ensureBadgeDefinitionsExist(badges: entry.badges, existingDefinitions: &badgeDefinitions, on: req.db)
        let leafResult = try await ensureSCMDBLeaf(
            parentId: currentParentId,
            name: entry.itemName,
            itemCode: entry.itemCode,
            badges: entry.badges,
            items: &allItems,
            index: &itemIndex,
            itemCodeIndex: &itemCodeIndex,
            dryRun: dryRun,
            db: req.db
        )
        if leafResult.created { inserted += 1 } else { skipped += 1 }
        if let leafId = leafResult.item.id, !entry.resources.isEmpty {
            recipesByBlueprintId[leafId] = entry.resources
        }
    }

    let resourcesSectionKey = scmdbLookupKey(parentId: nil, name: scmdbSectionResources)
    guard let resourcesSectionId = itemIndex[resourcesSectionKey]?.id else {
        throw Abort(.internalServerError, reason: "SCMDB resources section has no id")
    }
    if !dryRun {
        try await deleteLegacySCMDBResourceChildren(resourcesSectionId: resourcesSectionId, req: req)
        allItems = try await Blueprint.query(on: req.db)
            .filter(\.$category == .blueprints)
            .all()
        itemIndex = buildSCMDBLookupIndex(from: allItems)
        itemCodeIndex = buildSCMDBItemCodeIndex(from: allItems)
    }

    for resourceGroup in [scmdbSectionHandminable, scmdbSectionShipminable] {
        let groupBadges = [scmdbImportBadge, scmdbSectionResources, resourceGroup]
        try await ensureBadgeDefinitionsExist(badges: groupBadges, existingDefinitions: &badgeDefinitions, on: req.db)
        let result = try await ensureSCMDBNode(
            parentId: resourcesSectionId,
            name: resourceGroup,
            description: nil,
            itemCode: nil,
            badges: groupBadges,
            items: &allItems,
            index: &itemIndex,
            dryRun: dryRun,
            db: req.db
        )
        if result.created { inserted += 1 } else { skipped += 1 }
    }

    for resourceEntry in resourceEntries {
        let parentKey = scmdbLookupKey(parentId: resourcesSectionId, name: resourceEntry.group)
        guard let resourceGroupId = itemIndex[parentKey]?.id else {
            throw Abort(.internalServerError, reason: "SCMDB resource group '\(resourceEntry.group)' has no id")
        }
        let badges = [scmdbImportBadge, scmdbSectionResources, "Ressource", resourceEntry.group]
        try await ensureBadgeDefinitionsExist(badges: badges, existingDefinitions: &badgeDefinitions, on: req.db)
        let result = try await ensureSCMDBNode(
            parentId: resourceGroupId,
            name: resourceEntry.name,
            description: nil,
            itemCode: nil,
            badges: badges,
            items: &allItems,
            index: &itemIndex,
            dryRun: dryRun,
            db: req.db
        )
        if result.created { inserted += 1 } else { skipped += 1 }
    }

    if !dryRun {
        let resourceItems = allItems.filter { decodeSCMDBBadges($0.badgesCSV).contains("Ressource") }
        var resourcesByName: [String: Blueprint] = [:]
        for resource in resourceItems where resourcesByName[resource.name.lowercased()] == nil {
            resourcesByName[resource.name.lowercased()] = resource
        }
        try await rebuildSCMDBRecipeResources(
            recipesByBlueprintId: recipesByBlueprintId,
            resourcesByName: resourcesByName,
            db: req.db
        )
        try await deleteEmptySCMDBContainerNodes(on: req.db)
    }

    if !dryRun {
        await recordAuditEvent(
            on: req,
            actor: actor,
            action: "scmdb.import",
            entityType: "storage_item",
            entityId: craftingSection.item.id,
            details: "source=\(sourceBaseURL),mode=\(sourceData.sourceLabel),version=\(sourceData.version),inserted=\(inserted),skipped=\(skipped)"
        )
    }

    let preview = (
        craftingEntries.prefix(20).map { SCMDBImportPreviewItemDTO(section: $0.section, name: $0.itemName) } +
        resourceEntries.prefix(8).map { SCMDBImportPreviewItemDTO(section: "\(scmdbSectionResources) / \($0.group)", name: $0.name) }
    )

    return .init(
        sourceBaseURL: sourceBaseURL,
        version: sourceData.version,
        sourceLabel: sourceData.sourceLabel,
        snapshotUpdated: sourceData.snapshotUpdated,
        totalDiscovered: craftingEntries.count + resourceEntries.count,
        sectionCounts: [
            scmdbSectionWeapons: craftingEntries.filter { $0.section == scmdbSectionWeapons }.count,
            "\(scmdbSectionVehicle) / \(scmdbSectionWeapons)": craftingEntries.filter { $0.section == "\(scmdbSectionVehicle) / \(scmdbSectionWeapons)" }.count,
            "\(scmdbSectionVehicle) / \(scmdbSectionVehicleComponents)": craftingEntries.filter { $0.section == "\(scmdbSectionVehicle) / \(scmdbSectionVehicleComponents)" }.count,
            scmdbSectionArmor: craftingEntries.filter { $0.section == scmdbSectionArmor }.count,
            scmdbSectionOtherCrafting: craftingEntries.filter { $0.section == scmdbSectionOtherCrafting }.count,
            scmdbSectionResources: resourceEntries.count,
            scmdbSectionHandminable: resourceEntries.filter { $0.group == scmdbSectionHandminable }.count,
            scmdbSectionShipminable: resourceEntries.filter { $0.group == scmdbSectionShipminable }.count
        ],
        inserted: inserted,
        skipped: skipped,
        preview: Array(preview)
    )
}





