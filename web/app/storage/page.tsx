"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../_components/ui/Badge";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type LocationFilter = { id: string; label: string };
type LocationNode = { id: string; parentId?: string | null; name: string; description?: string | null; children: LocationNode[] };
type ItemNode = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  totalQty: number;
  entryCount: number;
  locations: LocationFilter[];
  children: ItemNode[];
};
type StorageListResponse = {
  items: ItemNode[];
  availableBadges: string[];
  locations: LocationNode[];
  locationFilters: LocationFilter[];
};

function toggleValue(values: string[], value: string) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

function parseBadges(input: string) {
  return input.split(",").map((item) => item.trim()).filter(Boolean);
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

function filterTree(nodes: ItemNode[], search: string, activeBadges: string[], activeLocations: string[]): ItemNode[] {
  const needle = search.trim().toLowerCase();
  const badgeSet = new Set(activeBadges.map((item) => item.toLowerCase()));
  const locationSet = new Set(activeLocations);

  return nodes.flatMap((node) => {
    const filteredChildren = filterTree(node.children, search, activeBadges, activeLocations);
    const matchesSearch =
      needle.length === 0 ||
      node.name.toLowerCase().includes(needle) ||
      (node.description ?? "").toLowerCase().includes(needle) ||
      (node.itemCode ?? "").toLowerCase().includes(needle) ||
      node.badges.some((badge) => badge.toLowerCase().includes(needle)) ||
      node.locations.some((location) => location.label.toLowerCase().includes(needle));
    const matchesBadges = badgeSet.size === 0 || node.badges.some((badge) => badgeSet.has(badge.toLowerCase()));
    const matchesLocations = locationSet.size === 0 || node.locations.some((location) => locationSet.has(location.id));

    if (filteredChildren.length > 0 || (matchesSearch && matchesBadges && matchesLocations)) {
      return [{ ...node, children: filteredChildren }];
    }
    return [];
  });
}

function ItemBranch({
  node,
  depth = 0,
  editMode,
  draggedId,
  moveBusyId,
  collapsedIds,
  onToggleCollapse,
  onDragStart,
  onDragEnd,
  onDropOnNode
}: {
  node: ItemNode;
  depth?: number;
  editMode: boolean;
  draggedId: string | null;
  moveBusyId: string | null;
  collapsedIds: string[];
  onToggleCollapse: (nodeId: string) => void;
  onDragStart: (node: ItemNode) => void;
  onDragEnd: () => void;
  onDropOnNode: (node: ItemNode) => void;
}) {
  const canDropHere = editMode && draggedId !== null && draggedId !== node.id && moveBusyId === null;
  const hasChildren = node.children.length > 0;
  const isCollapsed = collapsedIds.includes(node.id);

  return (
    <div style={{ marginLeft: depth * 18, marginTop: depth === 0 ? 0 : 10 }}>
      <div
        className="qb-inline"
        style={{
          justifyContent: "space-between",
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
            <a href={`/storage/${node.id}`}><strong>{node.name}</strong></a>
          </div>
          <div className="qb-muted">{node.totalQty} Bestand | {node.entryCount} Eintraege</div>
        </div>
        <div className="qb-inline" style={{ flexWrap: "wrap", justifyContent: "flex-end" }}>
          {node.badges.map((badge) => <Badge key={badge} label={badge} />)}
        </div>
      </div>
      {node.description ? <div className="qb-muted">{node.description}</div> : null}
      {editMode ? <div className="qb-muted">Hier ablegen, um den Eintrag unter {node.name} einzuordnen.</div> : null}
      {!isCollapsed ? node.children.map((child) => (
        <ItemBranch
          key={child.id}
          node={child}
          depth={depth + 1}
          editMode={editMode}
          draggedId={draggedId}
          moveBusyId={moveBusyId}
          collapsedIds={collapsedIds}
          onToggleCollapse={onToggleCollapse}
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
  onToggleFilter: (nodeId: string) => void;
  onDragStart: (node: LocationNode) => void;
  onDragEnd: () => void;
  onDropOnNode: (node: LocationNode) => void;
}) {
  const hasChildren = node.children.length > 0;
  const isCollapsed = collapsedIds.includes(node.id);
  const canDropHere = editMode && draggedId !== null && draggedId !== node.id && moveBusyId === null;

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
            variant={activeLocations.includes(node.id) ? "primary" : "secondary"}
            onClick={() => onToggleFilter(node.id)}
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

export default function StoragePage() {
  const [data, setData] = useState<StorageListResponse | null>(null);
  const [role, setRole] = useState<UserRole | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [itemEditMode, setItemEditMode] = useState(false);
  const [draggedItem, setDraggedItem] = useState<ItemNode | null>(null);
  const [itemMoveBusyId, setItemMoveBusyId] = useState<string | null>(null);
  const [collapsedItemIds, setCollapsedItemIds] = useState<string[]>([]);

  const [locationEditMode, setLocationEditMode] = useState(false);
  const [draggedLocation, setDraggedLocation] = useState<LocationNode | null>(null);
  const [locationMoveBusyId, setLocationMoveBusyId] = useState<string | null>(null);
  const [collapsedLocationIds, setCollapsedLocationIds] = useState<string[]>([]);

  const [search, setSearch] = useState("");
  const [activeBadges, setActiveBadges] = useState<string[]>([]);
  const [activeLocations, setActiveLocations] = useState<string[]>([]);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [itemCode, setItemCode] = useState("");
  const [selectedBadges, setSelectedBadges] = useState<string[]>([]);
  const [newBadgesInput, setNewBadgesInput] = useState("");

  const [locationName, setLocationName] = useState("");
  const [locationDescription, setLocationDescription] = useState("");
  const [locationParentId, setLocationParentId] = useState("");

  const canEdit = role !== null && role !== "guest";
  const canAdmin = role === "admin" || role === "superAdmin";

  async function loadAll() {
    setError(null);
    const [meRes, listRes] = await Promise.all([
      fetch("/api/me", { cache: "no-store" }),
      fetch("/api/storage/items", { cache: "no-store" })
    ]);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
    }

    if (!listRes.ok) {
      setError(`Lager load failed (${listRes.status})`);
      return;
    }

    setData((await listRes.json()) as StorageListResponse);
  }

  useEffect(() => {
    void loadAll();
  }, []);

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
      if (created?.id) window.location.href = `/storage/${created.id}`;
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

  const filteredItems = useMemo(
    () => filterTree(data?.items ?? [], search, activeBadges, activeLocations),
    [data, search, activeBadges, activeLocations]
  );
  const hasFilters = search.trim().length > 0 || activeBadges.length > 0 || activeLocations.length > 0;

  return (
    <main className="qb-main">
      <h1>Lager</h1>

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
              }}
              style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}
            >
              Filter zuruecksetzen
            </button>
          ) : null}
        </div>
        <TextInput placeholder="Suche nach Name, Badge, Location oder Item-Code" value={search} onChange={(e) => setSearch(e.target.value)} />
        <div className="qb-inline">
          {data?.availableBadges.map((badge) => (
            <Button
              key={badge}
              type="button"
              variant={activeBadges.includes(badge) ? "primary" : "secondary"}
              onClick={() => setActiveBadges((current) => toggleValue(current, badge))}
            >
              {badge}
            </Button>
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
                <span className="qb-muted">Filter und Struktur teilen sich dieselben Orte.</span>
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
                  onToggleFilter={(locationId) => setActiveLocations((current) => toggleValue(current, locationId))}
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
            <h2 className="qb-card-title">Gemeinsame Item-Stammdaten</h2>
            <p className="qb-muted">Die Struktur ist identisch zu Blueprints. Hier siehst du dieselben Eintraege mit Bestand pro Ort.</p>
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
            draggedId={draggedItem?.id ?? null}
            moveBusyId={itemMoveBusyId}
            collapsedIds={collapsedItemIds}
            onToggleCollapse={(nodeId) => setCollapsedItemIds((current) => toggleValue(current, nodeId))}
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
                <p className="qb-muted">Drag and Drop hilft dabei, falsch einsortierte Orte spaeter zu korrigieren.</p>
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
          <h2 className="qb-card-title">Neuen Oberpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createRootItem}>
            <TextInput placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={3} placeholder="Beschreibung" value={description} onChange={(e) => setDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
            <div className="qb-inline">
              {data?.availableBadges.map((badge) => (
                <Button
                  key={badge}
                  type="button"
                  variant={selectedBadges.includes(badge) ? "primary" : "secondary"}
                  onClick={() => setSelectedBadges((current) => toggleValue(current, badge))}
                >
                  {badge}
                </Button>
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
