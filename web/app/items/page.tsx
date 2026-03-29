"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../_components/ui/Badge";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type LocationFilter = { id: string; label: string };
type LocationNode = { id: string; parentId?: string | null; name: string; description?: string | null; children: LocationNode[] };
type BadgeDefinition = { name: string; groupName?: string | null };
type ItemNode = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  hideFromBlueprints: boolean;
  craftedByMe: boolean;
  crafterCount: number;
  totalQty: number;
  openSearchCount: number;
  entryCount: number;
  locations: LocationFilter[];
  children: ItemNode[];
};
type ItemsListResponse = {
  items: ItemNode[];
  availableBadges: string[];
  badgeDefinitions: BadgeDefinition[];
  locations: LocationNode[];
  locationFilters: LocationFilter[];
};

type SCMDBImportResult = {
  sourceBaseURL: string;
  version: string;
  totalDiscovered: number;
  sectionCounts: Record<string, number>;
  inserted: number;
  skipped: number;
  preview: { section: string; name: string }[];
};

const legacyScmdbDescriptions = new Set([
  "Importierte Crafting-Items aus SCMDB",
  "Craftbare Waffen aus SCMDB",
  "Craftbare Ruestungen aus SCMDB",
  "Weitere craftbare Items aus SCMDB",
  "Ressourcen aus SCMDB",
  "Handabbaubare Ressourcen aus SCMDB",
  "Schiffsabbaubare Ressourcen aus SCMDB"
]);

function visibleDescription(description?: string | null) {
  const value = description?.trim();
  return value && !legacyScmdbDescriptions.has(value) ? value : null;
}

function scmdbUrlForItemCode(itemCode?: string | null) {
  const value = itemCode?.trim();
  return value ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(value)}` : null;
}

function visibleBadges(badges: string[], itemCode?: string | null) {
  return badges.filter((badge) => badge !== "SCMDB" || Boolean(itemCode?.trim()));
}

function toggleValue(values: string[], value: string) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

function parseBadges(input: string) {
  return input.split(",").map((item) => item.trim()).filter(Boolean);
}

function itemSummaryParts(node: Pick<ItemNode, "crafterCount" | "totalQty" | "openSearchCount">) {
  const parts: string[] = [];
  if (node.crafterCount > 0) parts.push(`Crafter ${node.crafterCount}`);
  if (node.totalQty > 0) parts.push(`Lager ${node.totalQty}`);
  if (node.openSearchCount > 0) parts.push(`Suche ${node.openSearchCount}`);
  return parts;
}

function findItemById(nodes: ItemNode[], id: string): ItemNode | null {
  for (const node of nodes) {
    if (node.id === id) return node;
    const child = findItemById(node.children, id);
    if (child) return child;
  }
  return null;
}

function findLocationById(nodes: LocationNode[], id: string): LocationNode | null {
  for (const node of nodes) {
    if (node.id === id) return node;
    const child = findLocationById(node.children, id);
    if (child) return child;
  }
  return null;
}

function updateTreeNode(nodes: ItemNode[], targetId: string, updater: (node: ItemNode) => ItemNode): ItemNode[] {
  return nodes.map((node) => {
    if (node.id === targetId) {
      return updater(node);
    }
    if (node.children.length === 0) {
      return node;
    }
    const nextChildren = updateTreeNode(node.children, targetId, updater);
    if (nextChildren === node.children) {
      return node;
    }
    return { ...node, children: nextChildren };
  });
}

function collectCollapsedItemIdsBeyondDepth(nodes: ItemNode[], depth = 0): string[] {
  return nodes.flatMap((node) => [
    ...(node.children.length > 0 && depth >= 1 ? [node.id] : []),
    ...collectCollapsedItemIdsBeyondDepth(node.children, depth + 1)
  ]);
}

function collectCollapsibleLocationIds(nodes: LocationNode[]): string[] {
  return nodes.flatMap((node) => [
    ...(node.children.length > 0 ? [node.id] : []),
    ...collectCollapsibleLocationIds(node.children)
  ]);
}

function collectLocationSubtreeIds(node: LocationNode): string[] {
  return [node.id, ...node.children.flatMap((child) => collectLocationSubtreeIds(child))];
}

function groupBadgeDefinitions(definitions: BadgeDefinition[]) {
  const groups = new Map<string, BadgeDefinition[]>();
  for (const definition of definitions) {
    const group = definition.groupName?.trim() || "Ohne Gruppe";
    groups.set(group, [...(groups.get(group) ?? []), definition]);
  }
  return Array.from(groups.entries())
    .map(([groupName, badges]) => ({
      groupName,
      badges: badges.sort((left, right) => left.name.localeCompare(right.name, "de", { sensitivity: "base" }))
    }))
    .sort((left, right) => {
      if (left.groupName === "Ohne Gruppe") return 1;
      if (right.groupName === "Ohne Gruppe") return -1;
      return left.groupName.localeCompare(right.groupName, "de", { sensitivity: "base" });
    });
}

function filterTree(
  nodes: ItemNode[],
  search: string,
  activeBadges: string[],
  activeLocations: string[],
  resourcesOnly: boolean,
  wantedAndCraftableOnly: boolean
): ItemNode[] {
  const needle = search.trim().toLowerCase();
  const badgeSet = activeBadges.map((item) => item.toLowerCase());
  const locationSet = new Set(activeLocations);

  return nodes.flatMap((node) => {
    const directChildTotalQty = node.children.reduce((sum, child) => sum + child.totalQty, 0);
    const directChildOpenSearchCount = node.children.reduce((sum, child) => sum + child.openSearchCount, 0);
    const directChildEntryCount = node.children.reduce((sum, child) => sum + child.entryCount, 0);
    const ownTotalQty = Math.max(0, node.totalQty - directChildTotalQty);
    const ownOpenSearchCount = Math.max(0, node.openSearchCount - directChildOpenSearchCount);
    const ownEntryCount = Math.max(0, node.entryCount - directChildEntryCount);

    const filteredChildren = filterTree(
      node.children,
      search,
      activeBadges,
      activeLocations,
      resourcesOnly,
      wantedAndCraftableOnly
    );
    const matchesSearch =
      needle.length === 0 ||
      node.name.toLowerCase().includes(needle) ||
      (node.description ?? "").toLowerCase().includes(needle) ||
      (node.itemCode ?? "").toLowerCase().includes(needle) ||
      node.badges.some((badge) => badge.toLowerCase().includes(needle)) ||
      node.locations.some((location) => location.label.toLowerCase().includes(needle));
    const nodeBadgeSet = new Set(node.badges.map((badge) => badge.toLowerCase()));
    const matchesBadges = badgeSet.length === 0 || badgeSet.every((badge) => nodeBadgeSet.has(badge));
    const matchesLocations = locationSet.size === 0 || node.locations.some((location) => locationSet.has(location.id));
    const matchesResourceFilter = !resourcesOnly || node.badges.some((badge) => badge.toLowerCase() === "ressource");
    const matchesWantedCraftableFilter = !wantedAndCraftableOnly || (node.openSearchCount > 0 && node.crafterCount > 0);

    if (
      filteredChildren.length > 0 ||
      (matchesSearch &&
        matchesBadges &&
        matchesLocations &&
        matchesResourceFilter &&
        matchesWantedCraftableFilter)
    ) {
      return [{
        ...node,
        totalQty: ownTotalQty + filteredChildren.reduce((sum, child) => sum + child.totalQty, 0),
        openSearchCount: ownOpenSearchCount + filteredChildren.reduce((sum, child) => sum + child.openSearchCount, 0),
        entryCount: ownEntryCount + filteredChildren.reduce((sum, child) => sum + child.entryCount, 0),
        children: filteredChildren
      }];
    }
    return [];
  });
}

function ItemBranch({
  node,
  depth = 0,
  editMode,
  canQuickCraft,
  quickCraftBusyId,
  draggedId,
  moveBusyId,
  collapsedIds,
  onToggleCollapse,
  onToggleCraft,
  onDragStart,
  onDragEnd,
  onDropOnNode
}: {
  node: ItemNode;
  depth?: number;
  editMode: boolean;
  canQuickCraft: boolean;
  quickCraftBusyId: string | null;
  draggedId: string | null;
  moveBusyId: string | null;
  collapsedIds: string[];
  onToggleCollapse: (nodeId: string) => void;
  onToggleCraft: (node: ItemNode) => void;
  onDragStart: (node: ItemNode) => void;
  onDragEnd: () => void;
  onDropOnNode: (node: ItemNode) => void;
}) {
  const canDropHere = editMode && draggedId !== null && draggedId !== node.id && moveBusyId === null;
  const hasChildren = node.children.length > 0;
  const isCollapsed = collapsedIds.includes(node.id);
  const scmdbUrl = scmdbUrlForItemCode(node.itemCode);
  const displayBadges = visibleBadges(node.badges, node.itemCode);
  const displayDescription = visibleDescription(node.description);

  return (
    <div style={{ marginLeft: depth * 18, marginTop: depth === 0 ? 0 : 10, marginBottom: depth === 0 ? 14 : 0 }}>
      <div
        className="qb-inline"
        style={{
          justifyContent: "space-between",
          padding: editMode ? "8px 10px" : 0,
          border: editMode ? "1px dashed rgba(199, 205, 214, 0.25)" : "none",
          borderRadius: editMode ? 10 : 0,
          opacity: draggedId === node.id ? 0.5 : 1,
          gap: 12
        }}
        draggable={editMode}
        onDragStart={() => onDragStart(node)}
        onDragEnd={onDragEnd}
        onDragOver={(event) => {
          if (canDropHere) event.preventDefault();
        }}
        onDrop={(event) => {
          event.preventDefault();
          if (canDropHere) onDropOnNode(node);
        }}
      >
        <div>
          <div className="qb-inline" style={{ gap: 10 }}>
            {hasChildren ? (
              <button
                type="button"
                className="qb-nav-link"
                onClick={() => onToggleCollapse(node.id)}
                style={{ padding: "4px 8px", minWidth: 36 }}
              >
                {isCollapsed ? "+" : "-"}
              </button>
            ) : null}
            <a href={`/items/${node.id}`}><strong>{node.name}</strong></a>
          </div>
          {displayDescription ? <div className="qb-muted">{displayDescription}</div> : null}
          {itemSummaryParts(node).length > 0 ? <div className="qb-muted">{itemSummaryParts(node).join(" | ")}</div> : null}
        </div>
        <div className="qb-inline" style={{ flexWrap: "wrap", justifyContent: "flex-end", marginLeft: "auto" }}>
          {node.hideFromBlueprints ? <Badge label="In Blueprints ausgeblendet" /> : null}
          {displayBadges.map((badge) => (
            badge === "SCMDB" && scmdbUrl ? (
              <a
                key={`${node.id}-scmdb`}
                href={scmdbUrl}
                target="_blank"
                rel="noreferrer"
                className="qb-badge qb-badge-highlight"
              >
                SCMDB
              </a>
            ) : (
              <Badge key={`${node.id}-${badge}`} label={badge} />
            )
          ))}
          {canQuickCraft ? (
            <Button
              type="button"
              variant={node.craftedByMe ? "secondary" : "primary"}
              disabled={quickCraftBusyId !== null}
              onClick={() => onToggleCraft(node)}
            >
              {quickCraftBusyId === node.id ? "Speichert..." : node.craftedByMe ? "Kann ich nicht mehr craften" : "Ich kann craften"}
            </Button>
          ) : null}
        </div>
      </div>
      {!isCollapsed ? node.children.map((child) => (
        <ItemBranch
          key={child.id}
          node={child}
          depth={depth + 1}
          editMode={editMode}
          canQuickCraft={canQuickCraft}
          quickCraftBusyId={quickCraftBusyId}
          draggedId={draggedId}
          moveBusyId={moveBusyId}
          collapsedIds={collapsedIds}
          onToggleCollapse={onToggleCollapse}
          onToggleCraft={onToggleCraft}
          onDragStart={onDragStart}
          onDragEnd={onDragEnd}
          onDropOnNode={onDropOnNode}
        />
      )) : null}
    </div>
  );
}

function LocationBranch({
  node,
  depth = 0,
  editMode,
  draggedId,
  moveBusyId,
  collapsedIds,
  activeLocations,
  onToggleCollapse,
  onToggleFilter,
  onDragStart,
  onDragEnd,
  onDropOnNode
}: {
  node: LocationNode;
  depth?: number;
  editMode: boolean;
  draggedId: string | null;
  moveBusyId: string | null;
  collapsedIds: string[];
  activeLocations: string[];
  onToggleCollapse: (nodeId: string) => void;
  onToggleFilter: (node: LocationNode) => void;
  onDragStart: (node: LocationNode) => void;
  onDragEnd: () => void;
  onDropOnNode: (node: LocationNode) => void;
}) {
  const hasChildren = node.children.length > 0;
  const isCollapsed = collapsedIds.includes(node.id);
  const canDropHere = editMode && draggedId !== null && draggedId !== node.id && moveBusyId === null;
  const subtreeIds = collectLocationSubtreeIds(node);
  const isFilterActive = subtreeIds.every((id) => activeLocations.includes(id));

  return (
    <div style={{ marginLeft: depth * 18, marginTop: depth === 0 ? 0 : 10 }}>
      <div
        className="qb-inline"
        style={{
          justifyContent: "space-between",
          gap: 12,
          padding: editMode ? "8px 10px" : 0,
          border: editMode ? "1px dashed rgba(199, 205, 214, 0.25)" : "none",
          borderRadius: editMode ? 10 : 0,
          opacity: draggedId === node.id ? 0.5 : 1
        }}
        draggable={editMode}
        onDragStart={() => onDragStart(node)}
        onDragEnd={onDragEnd}
        onDragOver={(event) => {
          if (canDropHere) event.preventDefault();
        }}
        onDrop={(event) => {
          event.preventDefault();
          if (canDropHere) onDropOnNode(node);
        }}
      >
        <div className="qb-inline" style={{ gap: 10 }}>
          {hasChildren ? (
            <button
              type="button"
              className="qb-nav-link"
              onClick={() => onToggleCollapse(node.id)}
              style={{ padding: "4px 8px", minWidth: 36 }}
            >
              {isCollapsed ? "+" : "-"}
            </button>
          ) : null}
          <Button
            type="button"
            variant={isFilterActive ? "primary" : "secondary"}
            onClick={() => onToggleFilter(node)}
          >
            {node.name}
          </Button>
        </div>
        {editMode ? <span className="qb-muted">Hier ablegen, um den Ort unter {node.name} einzuordnen.</span> : null}
      </div>
      {node.description ? <div className="qb-muted">{node.description}</div> : null}
      {!isCollapsed ? node.children.map((child) => (
        <LocationBranch
          key={child.id}
          node={child}
          depth={depth + 1}
          editMode={editMode}
          draggedId={draggedId}
          moveBusyId={moveBusyId}
          collapsedIds={collapsedIds}
          activeLocations={activeLocations}
          onToggleCollapse={onToggleCollapse}
          onToggleFilter={onToggleFilter}
          onDragStart={onDragStart}
          onDragEnd={onDragEnd}
          onDropOnNode={onDropOnNode}
        />
      )) : null}
    </div>
  );
}

export default function ItemsPage() {
  const [data, setData] = useState<ItemsListResponse | null>(null);
  const [role, setRole] = useState<UserRole | null>(null);
  const [meUserId, setMeUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [quickCraftBusyId, setQuickCraftBusyId] = useState<string | null>(null);

  const [itemEditMode, setItemEditMode] = useState(false);
  const [draggedItem, setDraggedItem] = useState<ItemNode | null>(null);
  const [itemMoveBusyId, setItemMoveBusyId] = useState<string | null>(null);
  const [collapsedItemIds, setCollapsedItemIds] = useState<string[]>([]);
  const [defaultCollapsedItemsApplied, setDefaultCollapsedItemsApplied] = useState(false);

  const [locationEditMode, setLocationEditMode] = useState(false);
  const [draggedLocation, setDraggedLocation] = useState<LocationNode | null>(null);
  const [locationMoveBusyId, setLocationMoveBusyId] = useState<string | null>(null);
  const [collapsedLocationIds, setCollapsedLocationIds] = useState<string[]>([]);
  const [defaultCollapsedLocationsApplied, setDefaultCollapsedLocationsApplied] = useState(false);

  const [search, setSearch] = useState("");
  const [activeBadges, setActiveBadges] = useState<string[]>([]);
  const [activeLocations, setActiveLocations] = useState<string[]>([]);
  const [resourcesOnly, setResourcesOnly] = useState(false);
  const [wantedAndCraftableOnly, setWantedAndCraftableOnly] = useState(false);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [itemCode, setItemCode] = useState("");
  const [selectedBadges, setSelectedBadges] = useState<string[]>([]);
  const [newBadgesInput, setNewBadgesInput] = useState("");
  const [badgeName, setBadgeName] = useState("");
  const [badgeGroupName, setBadgeGroupName] = useState("");
  const [editingBadgeName, setEditingBadgeName] = useState<string | null>(null);
  const [editBadgeName, setEditBadgeName] = useState("");
  const [editBadgeGroupName, setEditBadgeGroupName] = useState("");
  const [badgeBusy, setBadgeBusy] = useState<string | null>(null);

  const [locationName, setLocationName] = useState("");
  const [locationDescription, setLocationDescription] = useState("");
  const [locationParentId, setLocationParentId] = useState("");
  const [scmdbSourceURL, setScmdbSourceURL] = useState("https://scmdb.net/?page=fab");
  const [importBusy, setImportBusy] = useState(false);
  const [importError, setImportError] = useState<string | null>(null);
  const [importResult, setImportResult] = useState<SCMDBImportResult | null>(null);
  const [collapsedBadgeGroups, setCollapsedBadgeGroups] = useState<string[]>([]);

  const canEdit = role !== null && role !== "guest";
  const canAdmin = role === "admin" || role === "superAdmin";
  const canQuickCraft = canEdit && meUserId !== null;
  const groupedBadgeDefinitions = useMemo(() => groupBadgeDefinitions(data?.badgeDefinitions ?? []), [data?.badgeDefinitions]);

  async function loadAll(fresh = false) {
    setError(null);
    const [meRes, listRes] = await Promise.all([
      fetch("/api/me", { cache: "no-store" }),
      fetch(fresh ? `/api/storage/items?fresh=${Date.now()}` : "/api/storage/items", {
        cache: fresh ? "no-store" : "default"
      })
    ]);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
      setMeUserId((me.userId as string | undefined) ?? null);
    }

    if (!listRes.ok) {
      setError(`Items load failed (${listRes.status})`);
      return;
    }

    setData((await listRes.json()) as ItemsListResponse);
  }

  useEffect(() => {
    void loadAll();
  }, []);

  useEffect(() => {
    if (!data || defaultCollapsedLocationsApplied) return;
    setCollapsedLocationIds(collectCollapsibleLocationIds(data.locations));
    setDefaultCollapsedLocationsApplied(true);
  }, [data, defaultCollapsedLocationsApplied]);

  useEffect(() => {
    if (!data || defaultCollapsedItemsApplied) return;
    setCollapsedItemIds(collectCollapsedItemIdsBeyondDepth(data.items));
    setDefaultCollapsedItemsApplied(true);
  }, [data, defaultCollapsedItemsApplied]);

  async function toggleCraftForNode(node: ItemNode) {
    if (!meUserId) return;
    setQuickCraftBusyId(node.id);
    setError(null);
    try {
      const res = node.craftedByMe
        ? await fetch(`/api/blueprints/${node.id}/crafters/${meUserId}`, { method: "DELETE" })
        : await fetch(`/api/blueprints/${node.id}/crafters`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({})
          });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Crafting-Status speichern fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setData((current) => {
        if (!current) return current;
        const delta = node.craftedByMe ? -1 : 1;
        return {
          ...current,
          items: updateTreeNode(current.items, node.id, (entry) => ({
            ...entry,
            craftedByMe: !entry.craftedByMe,
            crafterCount: Math.max(0, entry.crafterCount + delta)
          }))
        };
      });
      void loadAll(true);
    } finally {
      setQuickCraftBusyId(null);
    }
  }

  async function createRootItem(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/storage/items", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          description,
          itemCode: itemCode || null,
          badges: [...selectedBadges, ...parseBadges(newBadgesInput)]
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item create failed (${res.status}) ${text}`);
        return;
      }
      const created = await res.json();
      setName("");
      setDescription("");
      setItemCode("");
      setSelectedBadges([]);
      setNewBadgesInput("");
      await loadAll();
      if (created?.id) window.location.href = `/items/${created.id}`;
    } finally {
      setBusy(false);
    }
  }

  async function createLocation(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/storage/locations", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: locationName,
          description: locationDescription || null,
          parentId: locationParentId || null
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Location create failed (${res.status}) ${text}`);
        return;
      }
      setLocationName("");
      setLocationDescription("");
      setLocationParentId("");
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function moveItem(itemId: string, parentId: string | null) {
    if (!data) return;
    const source = findItemById(data.items, itemId);
    if (!source) return;

    setItemMoveBusyId(itemId);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${itemId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: source.name,
          description: source.description ?? "",
          itemCode: source.itemCode ?? null,
          badges: source.badges,
          hideFromBlueprints: source.hideFromBlueprints,
          parentId
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item verschieben fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setDraggedItem(null);
      await loadAll();
    } finally {
      setItemMoveBusyId(null);
    }
  }

  async function moveLocation(locationId: string, parentId: string | null) {
    if (!data) return;
    const source = findLocationById(data.locations, locationId);
    if (!source) return;

    setLocationMoveBusyId(locationId);
    setError(null);
    try {
      const res = await fetch(`/api/storage/locations/${locationId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: source.name,
          description: source.description ?? "",
          parentId
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Location verschieben fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setDraggedLocation(null);
      await loadAll();
    } finally {
      setLocationMoveBusyId(null);
    }
  }

  async function runSCMDBImport(dryRun: boolean) {
    setImportBusy(true);
    setImportError(null);
    setImportResult(null);
    try {
      const res = await fetch("/api/admin/items/import-scmdb", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sourceBaseURL: scmdbSourceURL || null,
          dryRun
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setImportError(`SCMDB-Import fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      const body = (await res.json()) as SCMDBImportResult;
      setImportResult(body);
      if (!dryRun) {
        await loadAll();
      }
    } finally {
      setImportBusy(false);
    }
  }

  async function createBadgeDefinition(e: FormEvent) {
    e.preventDefault();
    setBadgeBusy("create");
    setError(null);
    try {
      const res = await fetch("/api/admin/items/badges", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: badgeName,
          groupName: badgeGroupName || null
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Badge anlegen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setBadgeName("");
      setBadgeGroupName("");
      await loadAll();
    } finally {
      setBadgeBusy(null);
    }
  }

  async function saveBadgeDefinition(currentName: string) {
    setBadgeBusy(`save:${currentName}`);
    setError(null);
    try {
      const res = await fetch("/api/admin/items/badges", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          currentName,
          newName: editBadgeName,
          groupName: editBadgeGroupName || null
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Badge speichern fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setEditingBadgeName(null);
      setEditBadgeName("");
      setEditBadgeGroupName("");
      await loadAll();
    } finally {
      setBadgeBusy(null);
    }
  }

  async function deleteBadgeDefinition(name: string) {
    if (!window.confirm(`Badge "${name}" wirklich loeschen? Er wird auch aus allen Items entfernt.`)) return;
    setBadgeBusy(`delete:${name}`);
    setError(null);
    try {
      const res = await fetch("/api/admin/items/badges", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Badge loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBadgeBusy(null);
    }
  }

  async function deleteBadgeGroup(groupName: string) {
    const label = groupName || "Ohne Gruppe";
    if (!window.confirm(`Gruppe "${label}" wirklich loeschen? Alle Badges dieser Gruppe werden ebenfalls aus allen Items entfernt.`)) return;
    setBadgeBusy(`delete-group:${groupName}`);
    setError(null);
    try {
      const res = await fetch("/api/admin/items/badges", {
        method: "DELETE",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: "", groupName: groupName === "Ohne Gruppe" ? null : groupName })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Badge-Gruppe loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBadgeBusy(null);
    }
  }

  const filteredItems = useMemo(
    () =>
      filterTree(
        data?.items ?? [],
        search,
        activeBadges,
        activeLocations,
        resourcesOnly,
        wantedAndCraftableOnly
      ),
    [data, search, activeBadges, activeLocations, resourcesOnly, wantedAndCraftableOnly]
  );
  const hasFilters =
    search.trim().length > 0 ||
    activeBadges.length > 0 ||
    activeLocations.length > 0 ||
    resourcesOnly ||
    wantedAndCraftableOnly;

  return (
    <main className="qb-main">
      <h1>Items</h1>

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">Filter</h2>
          {hasFilters ? (
            <button
              type="button"
              className="qb-nav-link"
              onClick={() => {
                setSearch("");
                setActiveBadges([]);
                setActiveLocations([]);
                setResourcesOnly(false);
                setWantedAndCraftableOnly(false);
              }}
              style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}
            >
              Filter zuruecksetzen
            </button>
          ) : null}
        </div>
        <TextInput placeholder="Suche nach Name, Badge, Location oder Item-Code" value={search} onChange={(e) => setSearch(e.target.value)} />
        <div className="qb-inline" style={{ marginTop: 10, marginBottom: 10 }}>
          <Button type="button" variant={resourcesOnly ? "primary" : "secondary"} onClick={() => setResourcesOnly((value) => !value)}>
            Ressourcen vorhanden
          </Button>
          <Button
            type="button"
            variant={wantedAndCraftableOnly ? "primary" : "secondary"}
            onClick={() => setWantedAndCraftableOnly((value) => !value)}
          >
            Gesucht und craftbar
          </Button>
        </div>
        <div className="qb-grid" style={{ gap: 10 }}>
          {groupedBadgeDefinitions.length === 0 ? (
            <p className="qb-muted">Noch keine Badges vorhanden.</p>
          ) : groupedBadgeDefinitions.map((group) => (
            <div key={group.groupName} className="qb-grid" style={{ gap: 6 }}>
              <button
                type="button"
                className="qb-nav-link"
                onClick={() => setCollapsedBadgeGroups((current) => toggleValue(current, group.groupName))}
                style={{ textAlign: "left", padding: 0, background: "none", border: "none", cursor: "pointer" }}
              >
                <strong>{collapsedBadgeGroups.includes(group.groupName) ? "+ " : "- "}{group.groupName}</strong>
              </button>
              {!collapsedBadgeGroups.includes(group.groupName) ? (
                <div className="qb-inline">
                  {group.badges.map((badge) => (
                    <Button
                      key={badge.name}
                      type="button"
                      variant={activeBadges.includes(badge.name) ? "primary" : "secondary"}
                      onClick={() => setActiveBadges((current) => toggleValue(current, badge.name))}
                    >
                      {badge.name}
                    </Button>
                  ))}
                </div>
              ) : null}
            </div>
          ))}
        </div>
        <div className="qb-grid" style={{ gap: 8 }}>
          <strong>Lagerorte</strong>
          {data ? (
            <>
              <div
                className="qb-inline"
                style={{
                  justifyContent: "space-between",
                  padding: locationEditMode ? "8px 10px" : 0,
                  border: locationEditMode ? "1px dashed rgba(199, 205, 214, 0.25)" : "none",
                  borderRadius: locationEditMode ? 10 : 0
                }}
                onDragOver={(event) => {
                  if (locationEditMode && draggedLocation && locationMoveBusyId === null) event.preventDefault();
                }}
                onDrop={(event) => {
                  event.preventDefault();
                  if (locationEditMode && draggedLocation && locationMoveBusyId === null) void moveLocation(draggedLocation.id, null);
                }}
              >
                <span className="qb-muted">Locations filtern den gemeinsamen Item-Baum.</span>
                {locationEditMode ? <span className="qb-muted">Hier ablegen als Oberpunkt</span> : null}
              </div>
              {data.locations.map((location) => (
                <LocationBranch
                  key={location.id}
                  node={location}
                  editMode={locationEditMode}
                  draggedId={draggedLocation?.id ?? null}
                  moveBusyId={locationMoveBusyId}
                  collapsedIds={collapsedLocationIds}
                  activeLocations={activeLocations}
                  onToggleCollapse={(nodeId) => setCollapsedLocationIds((current) => toggleValue(current, nodeId))}
                  onToggleFilter={(locationNode) =>
                    setActiveLocations((current) => {
                      const subtreeIds = collectLocationSubtreeIds(locationNode);
                      const subtreeActive = subtreeIds.every((id) => current.includes(id));
                      if (subtreeActive) {
                        return current.filter((id) => !subtreeIds.includes(id));
                      }
                      return Array.from(new Set([...current, ...subtreeIds]));
                    })
                  }
                  onDragStart={setDraggedLocation}
                  onDragEnd={() => setDraggedLocation(null)}
                  onDropOnNode={(node) => {
                    if (draggedLocation) void moveLocation(draggedLocation.id, node.id);
                  }}
                />
              ))}
            </>
          ) : null}
        </div>
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <div
          className="qb-inline"
          style={{
            justifyContent: "space-between",
            padding: itemEditMode ? "8px 10px" : 0,
            border: itemEditMode ? "1px dashed rgba(199, 205, 214, 0.25)" : "none",
            borderRadius: itemEditMode ? 10 : 0
          }}
          onDragOver={(event) => {
            if (itemEditMode && draggedItem && itemMoveBusyId === null) event.preventDefault();
          }}
          onDrop={(event) => {
            event.preventDefault();
            if (itemEditMode && draggedItem && itemMoveBusyId === null) void moveItem(draggedItem.id, null);
          }}
        >
          <div>
            <h2 className="qb-card-title">Gemeinsamer Item-Baum</h2>
            <p className="qb-muted">Die Liste zeigt die gemeinsame Stammdatenstruktur. Details zu Crafting, Lager und Suche liegen jeweils auf der Detailseite des Items.</p>
          </div>
          {itemEditMode ? <span className="qb-muted">Hier ablegen als Oberpunkt</span> : null}
        </div>
        {filteredItems.length === 0 ? (
          <p className="qb-muted">Keine Eintraege fuer die gesetzten Filter.</p>
        ) : filteredItems.map((item) => (
          <ItemBranch
            key={item.id}
            node={item}
            editMode={itemEditMode}
            canQuickCraft={canQuickCraft}
            quickCraftBusyId={quickCraftBusyId}
            draggedId={draggedItem?.id ?? null}
            moveBusyId={itemMoveBusyId}
            collapsedIds={collapsedItemIds}
            onToggleCollapse={(nodeId) => setCollapsedItemIds((current) => toggleValue(current, nodeId))}
            onToggleCraft={(node) => void toggleCraftForNode(node)}
            onDragStart={setDraggedItem}
            onDragEnd={() => setDraggedItem(null)}
            onDropOnNode={(node) => {
              if (draggedItem) void moveItem(draggedItem.id, node.id);
            }}
          />
        ))}
      </Card>

      {(canAdmin || canEdit) ? (
        <Card>
          <h2 className="qb-card-title">Verwaltung</h2>
          {canAdmin ? (
            <>
              <div className="qb-form">
                <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                  <strong>Item-Struktur</strong>
                  <Button
                    type="button"
                    variant={itemEditMode ? "primary" : "secondary"}
                    onClick={() => {
                      setItemEditMode((value) => !value);
                      setDraggedItem(null);
                    }}
                  >
                    {itemEditMode ? "Bearbeiten beenden" : "Bearbeiten starten"}
                  </Button>
                </div>
                <p className="qb-muted">Nur Admins duerfen die gemeinsame Item-Struktur per Drag and Drop veraendern.</p>
              </div>
              <div className="qb-form">
                <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                  <strong>Location-Struktur</strong>
                  <Button
                    type="button"
                    variant={locationEditMode ? "primary" : "secondary"}
                    onClick={() => {
                      setLocationEditMode((value) => !value);
                      setDraggedLocation(null);
                    }}
                  >
                    {locationEditMode ? "Bearbeiten beenden" : "Bearbeiten starten"}
                  </Button>
                </div>
                <p className="qb-muted">Drag and Drop hilft dabei, Locations spaeter sauber umzubauen.</p>
              </div>
              <div className="qb-form">
                <strong>Badges</strong>
                <p className="qb-muted">Badges koennen hier zentral angelegt, gruppiert, umbenannt und geloescht werden.</p>
                <form className="qb-form" onSubmit={createBadgeDefinition}>
                  <TextInput placeholder="Badge-Name" value={badgeName} onChange={(e) => setBadgeName(e.target.value)} required />
                  <TextInput placeholder="Gruppe (optional)" value={badgeGroupName} onChange={(e) => setBadgeGroupName(e.target.value)} />
                  <Button type="submit" variant="primary" disabled={badgeBusy !== null}>
                    {badgeBusy === "create" ? "Speichert..." : "Badge anlegen"}
                  </Button>
                </form>
              {groupedBadgeDefinitions.length === 0 ? (
                  <p className="qb-muted">Noch keine Badges angelegt.</p>
                ) : groupedBadgeDefinitions.map((group) => (
                  <div key={group.groupName} className="qb-grid" style={{ gap: 8 }}>
                    <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                      <button
                        type="button"
                        className="qb-nav-link"
                        onClick={() => setCollapsedBadgeGroups((current) => toggleValue(current, group.groupName))}
                        style={{ textAlign: "left", padding: 0, background: "none", border: "none", cursor: "pointer" }}
                      >
                        <strong>{collapsedBadgeGroups.includes(group.groupName) ? "+ " : "- "}{group.groupName}</strong>
                      </button>
                      <Button
                        type="button"
                        variant="danger"
                        disabled={badgeBusy !== null}
                        onClick={() => void deleteBadgeGroup(group.groupName)}
                      >
                        Gruppe loeschen
                      </Button>
                    </div>
                    {!collapsedBadgeGroups.includes(group.groupName) ? group.badges.map((badge) => {
                      const isEditing = editingBadgeName === badge.name;
                      return (
                        <div key={badge.name} className="qb-inline" style={{ justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
                          <Badge label={badge.name} />
                          {isEditing ? (
                            <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                              <TextInput value={editBadgeName} onChange={(e) => setEditBadgeName(e.target.value)} placeholder="Badge-Name" />
                              <TextInput value={editBadgeGroupName} onChange={(e) => setEditBadgeGroupName(e.target.value)} placeholder="Gruppe (optional)" />
                              <Button type="button" variant="primary" disabled={badgeBusy !== null} onClick={() => void saveBadgeDefinition(badge.name)}>
                                Speichern
                              </Button>
                              <Button
                                type="button"
                                variant="secondary"
                                disabled={badgeBusy !== null}
                                onClick={() => {
                                  setEditingBadgeName(null);
                                  setEditBadgeName("");
                                  setEditBadgeGroupName("");
                                }}
                              >
                                Abbrechen
                              </Button>
                            </div>
                          ) : (
                            <div className="qb-inline" style={{ gap: 8 }}>
                              <Button
                                type="button"
                                variant="secondary"
                                disabled={badgeBusy !== null}
                                onClick={() => {
                                  setEditingBadgeName(badge.name);
                                  setEditBadgeName(badge.name);
                                  setEditBadgeGroupName(badge.groupName ?? "");
                                }}
                              >
                                Bearbeiten
                              </Button>
                              <Button type="button" variant="danger" disabled={badgeBusy !== null} onClick={() => void deleteBadgeDefinition(badge.name)}>
                                Loeschen
                              </Button>
                            </div>
                          )}
                        </div>
                      );
                    }) : null}
                  </div>
                ))}
              </div>
            </>
          ) : null}

          {canEdit ? (
            <form className="qb-form" onSubmit={createLocation}>
              <strong>Neuen Lagerort anlegen</strong>
              <SelectInput value={locationParentId} onChange={(e) => setLocationParentId(e.target.value)}>
                <option value="">Kein Oberpunkt</option>
                {data?.locationFilters.map((location) => (
                  <option key={location.id} value={location.id}>{location.label}</option>
                ))}
              </SelectInput>
              <TextInput placeholder="Location-Name" value={locationName} onChange={(e) => setLocationName(e.target.value)} required />
              <TextArea rows={3} placeholder="Beschreibung" value={locationDescription} onChange={(e) => setLocationDescription(e.target.value)} />
              <Button type="submit" variant="primary" disabled={busy}>
                {busy ? "Speichert..." : "Location anlegen"}
              </Button>
            </form>
          ) : null}
        </Card>
      ) : null}

      {canAdmin ? (
        <Card>
          <h2 className="qb-card-title">SCMDB Import</h2>
          <div className="qb-form">
            <TextInput
              placeholder="https://scmdb.net/?page=fab"
              value={scmdbSourceURL}
              onChange={(e) => setScmdbSourceURL(e.target.value)}
            />
            <div className="qb-inline">
              <Button type="button" variant="secondary" disabled={importBusy} onClick={() => void runSCMDBImport(true)}>
                {importBusy ? "Laeuft..." : "Preview laden"}
              </Button>
              <Button type="button" variant="primary" disabled={importBusy} onClick={() => void runSCMDBImport(false)}>
                {importBusy ? "Import laeuft..." : "Von SCMDB importieren"}
              </Button>
            </div>
            {importError ? <p className="qb-error">{importError}</p> : null}
            {importResult ? (
              <div className="qb-form" style={{ gap: 8 }}>
                <p className="qb-muted">
                  Quelle {importResult.sourceBaseURL}, Version {importResult.version}, gefunden {importResult.totalDiscovered}.
                </p>
                <p className="qb-muted">
                  Eingefuegt {importResult.inserted}, uebersprungen {importResult.skipped}.
                </p>
                <div className="qb-inline">
                  {Object.entries(importResult.sectionCounts).map(([section, count]) => (
                    <Badge key={section} label={`${section} ${count}`} />
                  ))}
                </div>
                {importResult.preview.length > 0 ? (
                  <div className="qb-grid" style={{ gap: 6 }}>
                    <strong>Preview</strong>
                    {importResult.preview.map((item) => (
                      <div key={`${item.section}-${item.name}`} className="qb-muted">
                        {item.section}: {item.name}
                      </div>
                    ))}
                  </div>
                ) : null}
              </div>
            ) : null}
          </div>
        </Card>
      ) : null}

      {canAdmin ? (
        <Card>
          <h2 className="qb-card-title">Neuen Oberpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createRootItem}>
            <TextInput placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={3} placeholder="Beschreibung" value={description} onChange={(e) => setDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
            <div className="qb-grid" style={{ gap: 10 }}>
              {groupedBadgeDefinitions.map((group) => (
                <div key={group.groupName} className="qb-grid" style={{ gap: 6 }}>
                  <button
                    type="button"
                    className="qb-nav-link"
                    onClick={() => setCollapsedBadgeGroups((current) => toggleValue(current, group.groupName))}
                    style={{ textAlign: "left", padding: 0, background: "none", border: "none", cursor: "pointer" }}
                  >
                    <strong>{collapsedBadgeGroups.includes(group.groupName) ? "+ " : "- "}{group.groupName}</strong>
                  </button>
                  {!collapsedBadgeGroups.includes(group.groupName) ? (
                    <div className="qb-inline">
                      {group.badges.map((badge) => (
                        <Button
                          key={badge.name}
                          type="button"
                          variant={selectedBadges.includes(badge.name) ? "primary" : "secondary"}
                          onClick={() => setSelectedBadges((current) => toggleValue(current, badge.name))}
                        >
                          {badge.name}
                        </Button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
            <TextInput placeholder="Neue Badges (kommagetrennt)" value={newBadgesInput} onChange={(e) => setNewBadgesInput(e.target.value)} />
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Speichert..." : "Oberpunkt anlegen"}
            </Button>
          </form>
        </Card>
      ) : null}
    </main>
  );
}
