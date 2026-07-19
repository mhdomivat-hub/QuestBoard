"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../_components/ui/Badge";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type Person = { userId: string; username: string };
type LocationFilter = { id: string; label: string };
type ItemNode = {
  id: string;
  name: string;
  itemCode?: string | null;
  badges: string[];
  hideFromBlueprints: boolean;
  craftedByMe: boolean;
  crafterCount: number;
  totalQty: number;
  openSearchCount: number;
  entryCount: number;
  people: Person[];
  locations: LocationFilter[];
  children: ItemNode[];
};
type LoadoutModuleSupportType = "MINING_LASER" | "FPS_WEAPON";
type ItemsListResponse = { items: ItemNode[]; backupMiningModules: BackupMiningModule[] };
type BackupMiningModule = { id: string; name: string; moduleType: LoadoutModuleSupportType };
type LoadoutType = "ARMOR" | "SHIP";
type LoadoutSummary = {
  id: string;
  name: string;
  description?: string | null;
  patchVersion: string;
  type: LoadoutType;
  itemCount: number;
  materialCount: number;
};
type LoadoutListResponse = { loadouts: LoadoutSummary[] };
type LoadoutItemRecipeResource = {
  resourceId: string;
  resourceName: string;
  badges: string[];
  slotName: string;
  quantity: number;
  minQuality?: number | null;
  minimumStoredQuantity: number;
};
type LoadoutAssignedModule = {
  referenceId: string;
  sourceType: "item" | "backup";
  itemId?: string | null;
  backupModuleId?: string | null;
  name: string;
  moduleType?: LoadoutModuleSupportType | null;
  itemCode?: string | null;
  badges: string[];
};

type ModuleAssignmentReference = {
  itemId?: string | null;
  backupModuleId?: string | null;
};

type ModuleCandidate = {
  referenceId: string;
  sourceType: "item" | "backup";
  itemId?: string | null;
  backupModuleId?: string | null;
  label: string;
  moduleType?: LoadoutModuleSupportType | null;
  itemCode?: string | null;
  badges: string[];
};

type LoadoutItem = {
  id: string;
  itemId: string;
  itemName: string;
  itemCode?: string | null;
  badges: string[];
  slotName?: string | null;
  quantity: number;
  sortOrder: number;
  moduleSupportType?: LoadoutModuleSupportType | null;
  assignedModules: LoadoutAssignedModule[];
  recipeResources: LoadoutItemRecipeResource[];
};

type LoadoutRequiredResource = {
  resourceId: string;
  resourceName: string;
  badges: string[];
  quantity: number;
  minimumStoredQuantity: number;
  effectiveRequiredQuantity: number;
  minQuality?: number | null;
  totalStoredQty: number;
  missingQty: number;
  missingForViability: number;
};
type LoadoutDetail = {
  id: string;
  name: string;
  description?: string | null;
  patchVersion: string;
  type: LoadoutType;
  items: LoadoutItem[];
  requiredResources: LoadoutRequiredResource[];
};

function scmdbUrlForItemCode(itemCode?: string | null) {
  const value = itemCode?.trim();
  return value ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(value)}` : null;
}

function visibleBadges(badges: string[], itemCode?: string | null) {
  return badges.filter((badge) => badge !== "SCMDB" || Boolean(itemCode?.trim()));
}


type FlatItem = {
  id: string;
  label: string;
  itemCode?: string | null;
  badges: string[];
};

function flattenItems(nodes: ItemNode[], path: string[] = []): FlatItem[] {
  return nodes.flatMap((node) => {
    const label = [...path, node.name].join(" / ");
    return [
      { id: node.id, label, itemCode: node.itemCode, badges: node.badges },
      ...flattenItems(node.children, [...path, node.name])
    ];
  });
}

function formatNumber(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/\.00$/, "");
}


function detectModuleSupportType(item: Pick<FlatItem, "label" | "itemCode" | "badges">): LoadoutModuleSupportType | null {
  const label = item.label.trim().toLowerCase();
  const itemCode = (item.itemCode ?? "").trim().toLowerCase();
  const badgeSet = new Set(item.badges.map((badge) => badge.toLowerCase()));

  if (label.includes("mining laser") || itemCode.includes("mining_laser") || itemCode.includes("weaponmining") || badgeSet.has("mining laser")) {
    return "MINING_LASER";
  }

  const weaponKeywords = ["pistol", "rifle", "smg", "sniper", "shotgun", "lmg", "weapon", "launcher"];
  const hasWeaponKeyword = weaponKeywords.some((keyword) => label.includes(keyword) || itemCode.includes(keyword));
  if (hasWeaponKeyword || badgeSet.has("waffe") || badgeSet.has("weapon") || badgeSet.has("fps")) {
    return "FPS_WEAPON";
  }

  return null;
}

function moduleSectionTitle(moduleSupportType?: LoadoutModuleSupportType | null) {
  switch (moduleSupportType) {
    case "FPS_WEAPON":
      return "FPS-Module";
    case "MINING_LASER":
      return "Mining-Module";
    default:
      return "Module";
  }
}
export default function LoadoutsPage() {
  const [role, setRole] = useState<UserRole | null>(null);
  const [items, setItems] = useState<FlatItem[]>([]);
  const [backupMiningModules, setBackupMiningModules] = useState<BackupMiningModule[]>([]);
  const [loadouts, setLoadouts] = useState<LoadoutSummary[]>([]);
  const [selectedLoadout, setSelectedLoadout] = useState<LoadoutDetail | null>(null);
  const [selectedLoadoutId, setSelectedLoadoutId] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [createPanelOpen, setCreatePanelOpen] = useState(false);
  const [editMode, setEditMode] = useState(false);

  const [newName, setNewName] = useState("");
  const [newDescription, setNewDescription] = useState("");
  const [newPatchVersion, setNewPatchVersion] = useState("");
  const [newType, setNewType] = useState<LoadoutType>("ARMOR");

  const [itemSearch, setItemSearch] = useState("");
  const [selectedItemId, setSelectedItemId] = useState("");
  const [quantity, setQuantity] = useState("1");
  const [moduleSearchByItemId, setModuleSearchByItemId] = useState<Record<string, string>>({});
  const [selectedModuleIdByItemId, setSelectedModuleIdByItemId] = useState<Record<string, string>>({});

  const [expandedRecipeResourceItemIds, setExpandedRecipeResourceItemIds] = useState<string[]>([]);
  async function fetchLoadoutDetail(loadoutId: string) {
    const res = await fetch(`/api/loadouts/${loadoutId}`, { cache: "no-store" });
    if (!res.ok) throw new Error(`Loadout konnte nicht geladen werden (${res.status}).`);
    const body = (await res.json()) as LoadoutDetail;
    setSelectedLoadout(body);
    setSelectedLoadoutId(body.id);
    setEditMode(false);
  }

  async function loadAll(preferredLoadoutId?: string) {
    const [meRes, itemsRes, loadoutsRes] = await Promise.all([
      fetch("/api/me", { cache: "no-store" }),
      fetch("/api/storage/items", { cache: "no-store" }),
      fetch("/api/loadouts", { cache: "no-store" })
    ]);

    if (!meRes.ok || !itemsRes.ok || !loadoutsRes.ok) {
      throw new Error("Daten konnten nicht geladen werden.");
    }

    const me = await meRes.json();
    const itemsBody = (await itemsRes.json()) as ItemsListResponse;
    const loadoutsBody = (await loadoutsRes.json()) as LoadoutListResponse;

    setRole((me.role as UserRole | undefined) ?? null);
    setItems(flattenItems(itemsBody.items));
    setBackupMiningModules(itemsBody.backupMiningModules ?? []);
    setLoadouts(loadoutsBody.loadouts);

    const nextId = preferredLoadoutId !== undefined ? preferredLoadoutId : (selectedLoadoutId || loadoutsBody.loadouts[0]?.id || "");
    if (nextId) {
      await fetchLoadoutDetail(nextId);
    } else {
      setSelectedLoadout(null);
      setSelectedLoadoutId("");
      setEditMode(false);
    }
  }

  useEffect(() => {
    void loadAll().catch((err: unknown) => setError(err instanceof Error ? err.message : "Unbekannter Fehler"));
  }, []);

  const filteredItems = useMemo(() => {
    const needle = itemSearch.trim().toLowerCase();
    const matches = !needle
      ? items
      : items.filter((item) =>
          item.label.toLowerCase().includes(needle) ||
          (item.itemCode ?? "").toLowerCase().includes(needle) ||
          item.badges.some((badge) => badge.toLowerCase().includes(needle))
        );
    return matches.slice(0, 15);
  }, [items, itemSearch]);

  function toModuleAssignmentReference(module: LoadoutAssignedModule): ModuleAssignmentReference {
    return module.sourceType === "backup"
      ? { backupModuleId: module.backupModuleId ?? null }
      : { itemId: module.itemId ?? null };
  }

  function allModuleCandidatesForItem(item: LoadoutItem): ModuleCandidate[] {
    if (!item.moduleSupportType) {
      return [];
    }

    const itemCandidates: ModuleCandidate[] = items
      .filter((candidate) => detectModuleSupportType(candidate) === item.moduleSupportType)
      .map((candidate) => ({
        referenceId: `item:${candidate.id}` ,
        sourceType: "item",
        itemId: candidate.id,
        moduleType: detectModuleSupportType(candidate),
        label: candidate.label,
        itemCode: candidate.itemCode,
        badges: candidate.badges
      }));
    const backupCandidates: ModuleCandidate[] = backupMiningModules
      .filter((candidate) => candidate.moduleType === item.moduleSupportType)
      .map((candidate) => ({
        referenceId: `backup:${candidate.id}` ,
        sourceType: "backup",
        backupModuleId: candidate.id,
        moduleType: candidate.moduleType,
        label: candidate.name,
        itemCode: null,
        badges: [candidate.moduleType === "FPS_WEAPON" ? "FPS-Backup" : "Mining-Backup"]
      }));
    return [...itemCandidates, ...backupCandidates].filter((candidate) => !(candidate.sourceType === "item" && candidate.itemId === item.itemId));
  }

  function moduleCandidatesForItem(item: LoadoutItem) {
    const term = (moduleSearchByItemId[item.id] ?? "").trim().toLowerCase();
    return allModuleCandidatesForItem(item)
      .filter((candidate) => {
        if (!term) return true;
        return [
          candidate.label,
          candidate.itemCode ?? "",
          ...candidate.badges
        ].some((value) => value.toLowerCase().includes(term));
      })
      .slice(0, 15);
  }

  const selectedItem = useMemo(
    () => items.find((item) => item.id === selectedItemId) ?? null,
    [items, selectedItemId]
  );

  async function createLoadout(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/loadouts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: newName,
          description: newDescription || null,
          patchVersion: newPatchVersion,
          type: newType
        })
      });
      if (!res.ok) throw new Error(`Loadout konnte nicht angelegt werden (${res.status}).`);
      const body = (await res.json()) as LoadoutDetail;
      setNewName("");
      setNewDescription("");
      setNewPatchVersion("");
      setNewType("ARMOR");
      setCreatePanelOpen(false);
      await loadAll(body.id);
    } finally {
      setBusy(false);
    }
  }

  async function saveLoadoutMeta(event: FormEvent) {
    event.preventDefault();
    if (!selectedLoadout || !editMode) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/loadouts/${selectedLoadout.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: selectedLoadout.name,
          description: selectedLoadout.description ?? null,
          patchVersion: selectedLoadout.patchVersion,
          type: selectedLoadout.type
        })
      });
      if (!res.ok) throw new Error(`Loadout konnte nicht gespeichert werden (${res.status}).`);
      await loadAll(selectedLoadout.id);
    } finally {
      setBusy(false);
    }
  }

  async function removeLoadout() {
    if (!selectedLoadout || !editMode) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/loadouts/${selectedLoadout.id}`, { method: "DELETE" });
      if (!res.ok) throw new Error(`Loadout konnte nicht geloescht werden (${res.status}).`);
      await loadAll("");
    } finally {
      setBusy(false);
    }
  }

  async function addLoadoutItem(event: FormEvent) {
    event.preventDefault();
    if (!selectedLoadout || !selectedItemId || !editMode) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/loadouts/${selectedLoadout.id}/items`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          itemId: selectedItemId,
          quantity: Math.max(1, Number(quantity) || 1),
          sortOrder: selectedLoadout.items.length
        })
      });
      if (!res.ok) throw new Error(`Teil konnte nicht hinzugefuegt werden (${res.status}).`);
      const body = (await res.json()) as LoadoutDetail;
      setSelectedItemId("");
      setItemSearch("");
      setQuantity("1");
      setSelectedLoadout(body);
      await fetchLoadoutDetail(body.id);
      setEditMode(true);
    } finally {
      setBusy(false);
    }
  }

  async function saveItem(item: LoadoutItem, moduleAssignments: ModuleAssignmentReference[] = item.assignedModules.map((module) => toModuleAssignmentReference(module))) {
    if (!selectedLoadout || !editMode) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/loadouts/${selectedLoadout.id}/items/${item.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          slotName: null,
          quantity: item.quantity,
          sortOrder: item.sortOrder,
          materialTargets: item.recipeResources.map((resource) => ({
            resourceId: resource.resourceId,
            slotName: resource.slotName,
            minQuality: resource.minQuality ?? null,
            minimumQuantity: Math.max(0, Number(resource.minimumStoredQuantity) || 0)
          })),
          moduleAssignments
        })
      });
      if (!res.ok) throw new Error(`Teil konnte nicht gespeichert werden (${res.status}).`);
      const body = (await res.json()) as LoadoutDetail;
      setSelectedLoadout(body);
      await fetchLoadoutDetail(body.id);
      setEditMode(true);
    } finally {
      setBusy(false);
    }
  }

  async function addModuleToItem(item: LoadoutItem) {
    const selectedReferenceId = selectedModuleIdByItemId[item.id] ?? "";
    const selectedCandidate = moduleCandidatesForItem(item).find((candidate) => candidate.referenceId === selectedReferenceId);
    if (!selectedCandidate) return;
    await saveItem(item, [
      ...item.assignedModules.map((module) => toModuleAssignmentReference(module)),
      selectedCandidate.sourceType === "backup"
        ? { backupModuleId: selectedCandidate.backupModuleId ?? null }
        : { itemId: selectedCandidate.itemId ?? null }
    ]);
    setModuleSearchByItemId((current) => ({ ...current, [item.id]: "" }));
    setSelectedModuleIdByItemId((current) => ({ ...current, [item.id]: "" }));
  }

  async function removeModuleFromItem(item: LoadoutItem, moduleIndex: number) {
    await saveItem(item, item.assignedModules.filter((_, index) => index !== moduleIndex).map((module) => toModuleAssignmentReference(module)));
  }

  async function deleteItem(itemId: string) {
    if (!selectedLoadout || !editMode) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/loadouts/${selectedLoadout.id}/items/${itemId}`, { method: "DELETE" });
      if (!res.ok) throw new Error(`Teil konnte nicht geloescht werden (${res.status}).`);
      const body = (await res.json()) as LoadoutDetail;
      setSelectedLoadout(body);
      await loadAll(body.id);
    } finally {
      setBusy(false);
    }
  }

  const canUseLoadouts = role !== null && role !== "guest";

  return (
    <main className="qb-page">
      <div className="qb-container qb-grid" style={{ gap: 18 }}>
        <div>
          <h1 className="qb-page-title">Loadouts</h1>
          <p className="qb-muted">Die Loadouts nutzen direkt die bestehende Itemliste als Grundlage. Zusaetzlich bekommt jetzt jedes Loadout eine Patch-Version, damit wir direkt sehen, fuer welchen Stand es gepflegt wurde.</p>

          {error ? <Card><p className="qb-error">{error}</p></Card> : null}

          {!canUseLoadouts ? <Card><p className="qb-muted">Loadouts stehen nur fuer eingeloggte Nutzer zur Verfuegung.</p></Card> : null}

          {canUseLoadouts ? (
            <div className="qb-grid qb-grid-2" style={{ gap: 18, alignItems: "start" }}>
              <div className="qb-grid" style={{ gap: 18 }}>
                <Card>
                  <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                    <h2 className="qb-card-title" style={{ margin: 0 }}>Neues Loadout</h2>
                    <Button type="button" variant="secondary" onClick={() => setCreatePanelOpen((current) => !current)}>
                      {createPanelOpen ? "Einklappen" : "Ausklappen"}
                    </Button>
                  </div>
                  {createPanelOpen ? (
                    <form className="qb-form" onSubmit={createLoadout} style={{ marginTop: 12 }}>
                      <TextInput placeholder="Name" value={newName} onChange={(event) => setNewName(event.target.value)} required />
                      <TextInput placeholder="Patch, z. B. 4.8.0" value={newPatchVersion} onChange={(event) => setNewPatchVersion(event.target.value)} required />
                      <TextArea rows={3} placeholder="Beschreibung" value={newDescription} onChange={(event) => setNewDescription(event.target.value)} />
                      <SelectInput value={newType} onChange={(event) => setNewType(event.target.value as LoadoutType)}>
                        <option value="ARMOR">Ruestung</option>
                        <option value="SHIP">Schiff</option>
                      </SelectInput>
                      <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Loadout anlegen"}</Button>
                    </form>
                  ) : <p className="qb-muted" style={{ marginTop: 12 }}>Der Bereich ist standardmaessig eingeklappt, damit im Alltag nichts versehentlich angelegt wird.</p>}
                </Card>

                <Card>
                  <h2 className="qb-card-title">Vorhandene Loadouts</h2>
                  {loadouts.length === 0 ? <p className="qb-muted">Noch keine Loadouts vorhanden.</p> : (
                    <div className="qb-grid" style={{ gap: 10 }}>
                      {loadouts.map((loadout) => (
                        <button
                          key={loadout.id}
                          type="button"
                          className="qb-nav-link"
                          style={{
                            textAlign: "left",
                            padding: 14,
                            borderRadius: 12,
                            border: loadout.id === selectedLoadoutId ? "1px solid rgba(142,197,255,0.85)" : "1px solid rgba(199,205,214,0.16)",
                            background: loadout.id === selectedLoadoutId ? "rgba(142,197,255,0.08)" : "rgba(255,255,255,0.02)"
                          }}
                          onClick={() => void fetchLoadoutDetail(loadout.id)}
                        >
                          <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                            <strong>{loadout.name}</strong>
                            <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                              <Badge label={`Patch ${loadout.patchVersion}`} />
                              <Badge label={loadout.type === "ARMOR" ? "Ruestung" : "Schiff"} />
                            </div>
                          </div>
                          {loadout.description ? <div className="qb-muted">{loadout.description}</div> : null}
                          <div className="qb-muted">{loadout.itemCount} Teile, {loadout.materialCount} Rezeptpositionen</div>
                        </button>
                      ))}
                    </div>
                  )}
                </Card>
              </div>

              <div className="qb-grid" style={{ gap: 18 }}>
                {selectedLoadout ? (
                  <>
                    <Card>
                      <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                        <div>
                          <h2 className="qb-card-title" style={{ margin: 0 }}>Loadout Details</h2>
                          <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap", marginTop: 8 }}>
                            <Badge label={`Patch ${selectedLoadout.patchVersion}`} />
                            <Badge label={selectedLoadout.type === "ARMOR" ? "Ruestung" : "Schiff"} />
                            <Badge label={editMode ? "Bearbeitungsmodus aktiv" : "Nur Lesen"} />
                          </div>
                        </div>
                        <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                          <Button type="button" variant={editMode ? "primary" : "secondary"} disabled={busy} onClick={() => setEditMode((current) => !current)}>
                            {editMode ? "Bearbeiten beenden" : "Bearbeiten"}
                          </Button>
                          {editMode ? <Button type="button" variant="danger" disabled={busy} onClick={() => void removeLoadout()}>Loadout loeschen</Button> : null}
                        </div>
                      </div>
                      {editMode ? (
                        <form className="qb-form" onSubmit={saveLoadoutMeta}>
                          <TextInput value={selectedLoadout.name} onChange={(event) => setSelectedLoadout((current) => current ? { ...current, name: event.target.value } : current)} required />
                          <TextInput value={selectedLoadout.patchVersion} onChange={(event) => setSelectedLoadout((current) => current ? { ...current, patchVersion: event.target.value } : current)} placeholder="Patch, z. B. 4.8.0" required />
                          <TextArea rows={3} value={selectedLoadout.description ?? ""} onChange={(event) => setSelectedLoadout((current) => current ? { ...current, description: event.target.value } : current)} />
                          <SelectInput value={selectedLoadout.type} onChange={(event) => setSelectedLoadout((current) => current ? { ...current, type: event.target.value as LoadoutType } : current)}>
                            <option value="ARMOR">Ruestung</option>
                            <option value="SHIP">Schiff</option>
                          </SelectInput>
                          <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Metadaten speichern"}</Button>
                        </form>
                      ) : (
                        <div className="qb-grid" style={{ gap: 10, marginTop: 12 }}>
                          <div><strong>{selectedLoadout.name}</strong></div>
                          {selectedLoadout.description ? <p className="qb-muted" style={{ margin: 0 }}>{selectedLoadout.description}</p> : null}
                          <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                            <Badge label={`${selectedLoadout.items.length} Teile`} />
                            <Badge label={`${selectedLoadout.requiredResources.length} Materialien`} />
                          </div>
                        </div>
                      )}
                    </Card>

                    {editMode ? (
                      <Card>
                        <h2 className="qb-card-title">Teil aus Itemliste hinzufuegen</h2>
                        <form className="qb-form" onSubmit={addLoadoutItem}>
                          <TextInput placeholder="Itemliste durchsuchen" value={itemSearch} onChange={(event) => setItemSearch(event.target.value)} />
                          {selectedItem ? <div className="qb-muted">Ausgewaehlt: {selectedItem.label}</div> : <div className="qb-muted">Waehle einen Treffer aus der Liste.</div>}
                          <div className="qb-grid" style={{ gap: 8, maxHeight: 280, overflowY: "auto" }}>
                            {filteredItems.length > 0 ? filteredItems.map((item) => (
                              <button
                                key={item.id}
                                type="button"
                                className="qb-nav-link"
                                style={{
                                  textAlign: "left",
                                  padding: 12,
                                  borderRadius: 10,
                                  border: item.id === selectedItemId ? "1px solid rgba(142,197,255,0.85)" : "1px solid rgba(199,205,214,0.16)",
                                  background: item.id === selectedItemId ? "rgba(142,197,255,0.08)" : "rgba(255,255,255,0.02)"
                                }}
                                onClick={() => setSelectedItemId(item.id)}
                              >
                                <div><strong>{item.label}</strong></div>
                                {(item.itemCode ?? "") || item.badges.length > 0 ? (
                                  <div className="qb-muted">
                                    {item.itemCode ? `Code ${item.itemCode}` : ""}
                                    {item.itemCode && item.badges.length > 0 ? " | " : ""}
                                    {item.badges.slice(0, 4).join(", ")}
                                  </div>
                                ) : null}
                              </button>
                            )) : <div className="qb-muted">Keine Treffer gefunden.</div>}
                          </div>
                          <TextInput type="number" min="1" placeholder="Menge" value={quantity} onChange={(event) => setQuantity(event.target.value)} />
                          <Button type="submit" variant="primary" disabled={busy || !selectedItemId}>{busy ? "Speichert..." : "Teil hinzufuegen"}</Button>
                        </form>
                      </Card>
                    ) : null}

                    <Card>
                      <h2 className="qb-card-title">Teile im Loadout</h2>
                      {selectedLoadout.items.length === 0 ? <p className="qb-muted">Dieses Loadout ist noch leer.</p> : (
                        <div className="qb-grid" style={{ gap: 10 }}>
                          {selectedLoadout.items.map((item) => {
                            const scmdbUrl = scmdbUrlForItemCode(item.itemCode);
                            const displayBadges = visibleBadges(item.badges, item.itemCode).slice(0, 4);
                            const resourcesExpanded = expandedRecipeResourceItemIds.includes(item.id);
                            return (
                              <div key={item.id} style={{ border: "1px solid rgba(199,205,214,0.16)", borderRadius: 12, padding: 12 }}>
                                <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "flex-start" }}>
                                  <div>
                                    <strong>{item.itemName}</strong>
                                    <div className="qb-muted">Menge {item.quantity}</div>
                                  </div>
                                  <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
                                    {item.recipeResources.length > 0 ? (
                                      <Button
                                        type="button"
                                        variant="secondary"
                                        onClick={() => setExpandedRecipeResourceItemIds((current) => current.includes(item.id) ? current.filter((entryId) => entryId !== item.id) : [...current, item.id])}
                                      >
                                        {resourcesExpanded ? "Ressourcen ausblenden" : "Ressourcen anzeigen"}
                                      </Button>
                                    ) : null}
                                    {displayBadges.map((badge) => badge === "SCMDB" && scmdbUrl ? (
                                      <a
                                        key={`${item.id}-scmdb`}
                                        href={scmdbUrl}
                                        target="_blank"
                                        rel="noreferrer"
                                        className="qb-badge qb-badge-highlight"
                                      >
                                        SCMDB
                                      </a>
                                    ) : (
                                      <Badge key={`${item.id}-${badge}`} label={badge} />
                                    ))}
                                    {editMode ? <Button type="button" variant="danger" disabled={busy} onClick={() => void deleteItem(item.id)}>Entfernen</Button> : null}
                                  </div>
                                </div>
                                {editMode ? (
                                  <div className="qb-inline" style={{ gap: 8, marginTop: 10, flexWrap: "wrap" }}>
                                    <TextInput type="number" min="1" value={String(item.quantity)} onChange={(event) => setSelectedLoadout((current) => current ? ({ ...current, items: current.items.map((entry) => entry.id === item.id ? { ...entry, quantity: Math.max(1, Number(event.target.value) || 1) } : entry) }) : current)} placeholder="Menge" />
                                    <Button type="button" variant="primary" disabled={busy} onClick={() => void saveItem(item)}>Teil speichern</Button>
                                  </div>
                                ) : null}
                                {item.moduleSupportType ? (
                                  <div className="qb-grid" style={{ gap: 8, marginTop: 10 }}>
                                    <strong>{moduleSectionTitle(item.moduleSupportType)}</strong>
                                    {item.assignedModules.length > 0 ? (
                                      <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                                        {item.assignedModules.map((module, moduleIndex) => (
                                          <div key={`${item.id}-${module.referenceId}-${moduleIndex}`} className="qb-inline" style={{ gap: 8, padding: "6px 10px", borderRadius: 10, border: "1px solid rgba(199,205,214,0.16)" }}>
                                            <span>{module.name}</span>
                                            {editMode ? <Button type="button" variant="danger" disabled={busy} onClick={() => void removeModuleFromItem(item, moduleIndex)}>Entfernen</Button> : null}
                                          </div>
                                        ))}
                                      </div>
                                    ) : <div className="qb-muted">Noch keine Module zugewiesen.</div>}
                                    {editMode ? (
                                      <>
                                        <TextInput placeholder="Module durchsuchen" value={moduleSearchByItemId[item.id] ?? ""} onChange={(event) => setModuleSearchByItemId((current) => ({ ...current, [item.id]: event.target.value }))} />
                                        {(selectedModuleIdByItemId[item.id] ?? "") ? <div className="qb-muted">Ausgewaehlt: {allModuleCandidatesForItem(item).find((candidate) => candidate.referenceId === (selectedModuleIdByItemId[item.id] ?? ""))?.label ?? "Modul"}</div> : <div className="qb-muted">Waehle ein Modul aus der Liste.</div>}
                                        <div className="qb-grid" style={{ gap: 8, maxHeight: 220, overflowY: "auto" }}>
                                          {moduleCandidatesForItem(item).length > 0 ? moduleCandidatesForItem(item).map((candidate) => (
                                            <button
                                              key={`${item.id}-${candidate.referenceId}`}
                                              type="button"
                                              className="qb-nav-link"
                                              style={{
                                                textAlign: "left",
                                                padding: 12,
                                                borderRadius: 10,
                                                border: candidate.referenceId === (selectedModuleIdByItemId[item.id] ?? "") ? "1px solid rgba(142,197,255,0.85)" : "1px solid rgba(199,205,214,0.16)",
                                                background: candidate.referenceId === (selectedModuleIdByItemId[item.id] ?? "") ? "rgba(142,197,255,0.08)" : "rgba(255,255,255,0.02)"
                                              }}
                                              onClick={() => setSelectedModuleIdByItemId((current) => ({ ...current, [item.id]: candidate.referenceId }))}
                                            >
                                              <div><strong>{candidate.label}</strong></div>
                                              {(candidate.itemCode ?? "") || candidate.badges.length > 0 ? (
                                                <div className="qb-muted">
                                                  {candidate.itemCode ? `Code ${candidate.itemCode}` : ""}
                                                  {candidate.itemCode && candidate.badges.length > 0 ? " | " : ""}
                                                  {candidate.badges.slice(0, 4).join(", ")}
                                                </div>
                                              ) : null}
                                            </button>
                                          )) : <div className="qb-muted">Keine passenden Module gefunden.</div>}
                                        </div>
                                        <Button type="button" variant="secondary" disabled={busy || !(selectedModuleIdByItemId[item.id] ?? "")} onClick={() => void addModuleToItem(item)}>Modul zuweisen</Button>
                                      </>
                                    ) : null}
                                  </div>
                                ) : null}
                                {item.recipeResources.length > 0 && resourcesExpanded ? (
                                  <div className="qb-grid" style={{ gap: 8, marginTop: 10 }}>
                                    {item.recipeResources.map((resource) => (
                                      <div key={`${item.id}-${resource.resourceId}-${resource.slotName}`} style={{ border: "1px solid rgba(199,205,214,0.12)", borderRadius: 10, padding: 10 }}>
                                        <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                                          <strong>{resource.slotName}: {resource.resourceName}</strong>
                                          {resource.badges.map((badge) => <Badge key={`${item.id}-${resource.resourceId}-${resource.slotName}-${badge}`} label={badge} />)}
                                        </div>
                                        <div className="qb-muted">Crafting {formatNumber(resource.quantity)}{resource.minQuality !== null && resource.minQuality !== undefined ? ` | MinQ ${resource.minQuality}` : ""}</div>
                                        {editMode ? (
                                          <TextInput
                                            type="number"
                                            min="1"
                                            step="1"
                                            value={String(resource.minimumStoredQuantity)}
                                            onChange={(event) => setSelectedLoadout((current) => current ? ({
                                              ...current,
                                              items: current.items.map((entry) => entry.id === item.id ? {
                                                ...entry,
                                                recipeResources: entry.recipeResources.map((entryResource) =>
                                                  entryResource.resourceId === resource.resourceId &&
                                                  entryResource.slotName === resource.slotName &&
                                                  (entryResource.minQuality ?? null) === (resource.minQuality ?? null)
                                                    ? { ...entryResource, minimumStoredQuantity: Math.max(1, Math.round(Number(event.target.value) || 0)) }
                                                    : entryResource
                                                )
                                              } : entry)
                                            }) : current)}
                                            placeholder="MinQ"
                                          />
                                        ) : null}
                                      </div>
                                    ))}
                                  </div>
                                ) : null}
                                {editMode && item.recipeResources.length === 0 ? <div className="qb-muted" style={{ marginTop: 10 }}>Keine Rezeptressourcen fuer dieses Teil hinterlegt.</div> : null}
                              </div>
                            );
                          })}
                        </div>
                      )}
                    </Card>

                    <Card>
                      <h2 className="qb-card-title">Gesamter Materialbedarf</h2>
                      {selectedLoadout.requiredResources.length === 0 ? <p className="qb-muted">Noch kein Materialbedarf vorhanden.</p> : (
                        <div className="qb-grid" style={{ gap: 8 }}>
                          {selectedLoadout.requiredResources.map((resource) => (
                            <div key={`${resource.resourceId}-${resource.minQuality ?? "any"}`} style={{ borderBottom: "1px solid rgba(199,205,214,0.12)", paddingBottom: 8 }}>
                              <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                                <strong>{resource.resourceName}</strong>
                                {resource.badges.map((badge) => <Badge key={`${resource.resourceId}-${resource.minQuality ?? "any"}-${badge}`} label={badge} />)}
                              </div>
                              <div className="qb-muted">Crafting {formatNumber(resource.quantity)}{resource.minQuality !== null && resource.minQuality !== undefined ? ` | MinQ ${resource.minQuality}` : ""}</div>
                              
                            </div>
                          ))}
                        </div>
                      )}
                    </Card>
                  </>
                ) : (
                  <Card><p className="qb-muted">Links ein Loadout auswaehlen oder ein neues anlegen.</p></Card>
                )}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </main>
  );
}





