"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type Person = { userId: string; username: string };
type LocationFilter = { id: string; label: string };
type BadgeDefinition = { name: string; groupName?: string | null };
type Entry = { id: string; userId: string; username: string; locationId: string; locationLabel: string; qty: number; note?: string | null; createdAt?: string | null };
type StorageChild = { id: string; name: string; itemCode?: string | null; badges: string[]; hideFromBlueprints: boolean; crafterCount: number; totalQty: number; openSearchCount: number; entryCount: number };
type Breadcrumb = { id: string; name: string };
type StorageDetail = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  availableBadges: string[];
  badgeDefinitions: BadgeDefinition[];
  hideFromBlueprints: boolean;
  breadcrumb: Breadcrumb[];
  children: StorageChild[];
  entries: Entry[];
  availableUsers: Person[];
  locationFilters: LocationFilter[];
};
type Crafter = { userId: string; username: string };
type BlueprintDetail = { id: string; crafters: Crafter[] };
type SearchOffer = { id: string; userId: string; username: string; note?: string | null };
type SearchRequest = {
  id: string;
  userId: string;
  username: string;
  averageQuality?: string | null;
  note?: string | null;
  status: "OPEN" | "FULFILLED" | "CANCELLED";
  offers: SearchOffer[];
};
type ItemSearchDetail = {
  id: string;
  requests: SearchRequest[];
};
type TreeNode = { id: string; name: string; children: TreeNode[] };
type ListResponse = { items: TreeNode[] };

function scmdbUrlForItemCode(itemCode?: string | null) {
  const value = itemCode?.trim();
  return value ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(value)}` : null;
}

function visibleBadges(badges: string[], itemCode?: string | null) {
  return badges.filter((badge) => badge !== "SCMDB" || Boolean(itemCode?.trim()));
}

function flattenItems(nodes: TreeNode[]): Array<{ id: string; name: string }> {
  const result: Array<{ id: string; name: string }> = [];
  const visit = (entries: TreeNode[], prefix = "") => {
    for (const entry of entries) {
      const label = prefix ? `${prefix} > ${entry.name}` : entry.name;
      result.push({ id: entry.id, name: label });
      visit(entry.children, label);
    }
  };
  visit(nodes);
  return result;
}

function parseBadges(input: string) {
  return input.split(",").map((item) => item.trim()).filter(Boolean);
}

function toggleValue(values: string[], value: string) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
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

export default function ItemDetailPage({ params }: { params: { id: string } }) {
  const [storageDetail, setStorageDetail] = useState<StorageDetail | null>(null);
  const [blueprintDetail, setBlueprintDetail] = useState<BlueprintDetail | null>(null);
  const [searchDetail, setSearchDetail] = useState<ItemSearchDetail | null>(null);
  const [role, setRole] = useState<UserRole | null>(null);
  const [meUserId, setMeUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [itemCode, setItemCode] = useState("");
  const [selectedBadges, setSelectedBadges] = useState<string[]>([]);
  const [newBadgesInput, setNewBadgesInput] = useState("");
  const [hideFromBlueprints, setHideFromBlueprints] = useState(false);

  const [childName, setChildName] = useState("");
  const [childDescription, setChildDescription] = useState("");
  const [childItemCode, setChildItemCode] = useState("");
  const [childSelectedBadges, setChildSelectedBadges] = useState<string[]>([]);
  const [childNewBadgesInput, setChildNewBadgesInput] = useState("");

  const [locationId, setLocationId] = useState("");
  const [qty, setQty] = useState(1);
  const [note, setNote] = useState("");
  const [entryUserId, setEntryUserId] = useState("");

  const [averageQuality, setAverageQuality] = useState("");
  const [requestNote, setRequestNote] = useState("");
  const [offerNotes, setOfferNotes] = useState<Record<string, string>>({});

  const [editingEntryId, setEditingEntryId] = useState<string | null>(null);
  const [editingEntryQty, setEditingEntryQty] = useState(1);
  const [editingEntryNote, setEditingEntryNote] = useState("");

  const [allItems, setAllItems] = useState<Array<{ id: string; name: string }>>([]);
  const [mergeTargetId, setMergeTargetId] = useState("");
  const [mergeKeepValuesFrom, setMergeKeepValuesFrom] = useState<"CURRENT" | "OTHER">("CURRENT");
  const [mergeParentChoice, setMergeParentChoice] = useState<"CURRENT" | "OTHER" | "ROOT">("CURRENT");
  const [collapsedBadgeGroups, setCollapsedBadgeGroups] = useState<string[]>([]);

  const canEdit = role !== null && role !== "guest";
  const canAdmin = role === "admin" || role === "superAdmin";
  const totalQty = useMemo(() => storageDetail?.entries.reduce((sum, entry) => sum + entry.qty, 0) ?? 0, [storageDetail]);
  const amCrafter = Boolean(blueprintDetail?.crafters.some((crafter) => crafter.userId === meUserId));
  const groupedBadgeDefinitions = useMemo(() => groupBadgeDefinitions(storageDetail?.badgeDefinitions ?? []), [storageDetail?.badgeDefinitions]);
  const scmdbUrl = useMemo(() => scmdbUrlForItemCode(storageDetail?.itemCode), [storageDetail?.itemCode]);

  async function loadAll() {
    setError(null);
    const requests: Promise<Response>[] = [
      fetch("/api/me", { cache: "no-store" }),
      fetch(`/api/storage/items/${params.id}`, { cache: "no-store" }),
      fetch(`/api/blueprints/${params.id}`, { cache: "no-store" }),
      fetch(`/api/item-search/${params.id}`, { cache: "no-store" })
    ];
    if (canAdmin) {
      requests.push(fetch("/api/storage/items", { cache: "no-store" }));
    }

    const [meRes, storageRes, blueprintRes, searchRes, listRes] = await Promise.all(requests);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
      setMeUserId((me.userId as string | undefined) ?? null);
      setEntryUserId((me.userId as string | undefined) ?? "");
    }

    if (!storageRes.ok || !blueprintRes.ok || !searchRes.ok) {
      setError(`Item load failed (${storageRes.status}/${blueprintRes.status}/${searchRes.status})`);
      return;
    }

    const storageBody = (await storageRes.json()) as StorageDetail;
    const blueprintBody = (await blueprintRes.json()) as BlueprintDetail;
    const searchBody = (await searchRes.json()) as ItemSearchDetail;

    setStorageDetail(storageBody);
    setBlueprintDetail(blueprintBody);
    setSearchDetail(searchBody);
    setName(storageBody.name);
    setDescription(storageBody.description ?? "");
    setItemCode(storageBody.itemCode ?? "");
    setSelectedBadges(storageBody.badges);
    setHideFromBlueprints(storageBody.hideFromBlueprints);
    if (!locationId && storageBody.locationFilters[0]) setLocationId(storageBody.locationFilters[0].id);

    if (listRes?.ok) {
      const listBody = (await listRes.json()) as ListResponse;
      setAllItems(flattenItems(listBody.items).filter((item) => item.id !== storageBody.id));
    } else {
      setAllItems([]);
    }
  }

  useEffect(() => {
    void loadAll();
  }, [params.id, canAdmin]);

  async function saveItem(e: FormEvent) {
    e.preventDefault();
    if (!storageDetail) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${params.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          description,
          itemCode: itemCode || null,
          badges: [...selectedBadges, ...parseBadges(newBadgesInput)],
          hideFromBlueprints,
          parentId: storageDetail.parentId ?? null
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item update failed (${res.status}) ${text}`);
        return;
      }
      await loadAll();
      setNewBadgesInput("");
    } finally {
      setBusy(false);
    }
  }

  async function createChild(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/storage/items", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          parentId: params.id,
          name: childName,
          description: childDescription,
          itemCode: childItemCode || null,
          badges: [...childSelectedBadges, ...parseBadges(childNewBadgesInput)]
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Unterpunkt create failed (${res.status}) ${text}`);
        return;
      }
      const created = await res.json();
      if (created?.id) {
        window.location.href = `/items/${created.id}`;
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function toggleCraftSelf() {
    if (!blueprintDetail || !meUserId) return;
    setBusy(true);
    setError(null);
    try {
      const res = amCrafter
        ? await fetch(`/api/blueprints/${blueprintDetail.id}/crafters/${meUserId}`, { method: "DELETE" })
        : await fetch(`/api/blueprints/${blueprintDetail.id}/crafters`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({})
          });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Crafter update failed (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createEntry(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${params.id}/entries`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ locationId, qty, note: note || null, userId: canAdmin ? (entryUserId || null) : null })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Lager-Eintrag create failed (${res.status}) ${text}`);
        return;
      }
      setQty(1);
      setNote("");
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function saveEntry(entryId: string) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/entries/${entryId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ qty: editingEntryQty, note: editingEntryNote || null })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Eintrag update fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
      setEditingEntryId(null);
      setEditingEntryQty(1);
      setEditingEntryNote("");
    } finally {
      setBusy(false);
    }
  }

  async function deleteEntry(entryId: string) {
    if (!window.confirm("Eintrag wirklich loeschen?")) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/entries/${entryId}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Eintrag loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createRequest(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/${params.id}/requests`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          averageQuality: averageQuality || null,
          note: requestNote || null
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche anlegen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      setAverageQuality("");
      setRequestNote("");
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createOffer(requestId: string) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}/offers`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ note: offerNotes[requestId] || null })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Angebot speichern fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setOfferNotes((current) => ({ ...current, [requestId]: "" }));
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function updateRequestStatus(requestId: string, status: "FULFILLED" | "CANCELLED") {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche aktualisieren fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function deleteRequest(requestId: string) {
    if (!window.confirm("Suchanfrage wirklich loeschen?")) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function mergeItems(e: FormEvent) {
    e.preventDefault();
    if (!mergeTargetId) {
      setError("Bitte zweiten Eintrag zum Zusammenfuehren auswaehlen.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${params.id}/merge`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          otherItemId: mergeTargetId,
          keepValuesFrom: mergeKeepValuesFrom,
          parentChoice: mergeParentChoice
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Zusammenfuehren fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      const merged = await res.json();
      if (merged?.id) {
        window.location.href = `/items/${merged.id}`;
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function deleteItem() {
    if (!storageDetail || !window.confirm(`Eintrag "${storageDetail.name}" wirklich komplett loeschen?`)) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${storageDetail.id}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      window.location.href = "/items";
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="qb-main">
      <h1>Item</h1>
      {storageDetail ? (
        <div className="qb-inline" style={{ marginBottom: 12, flexWrap: "wrap" }}>
          {storageDetail.breadcrumb.map((item, index) => (
            <span key={item.id} className="qb-muted">
              {index > 0 ? " > " : ""}
              <a href={`/items/${item.id}`}>{item.name}</a>
            </span>
          ))}
        </div>
      ) : null}

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">{storageDetail?.name ?? "Item"}</h2>
          <div className="qb-inline" style={{ flexWrap: "wrap" }}>
            {storageDetail?.hideFromBlueprints ? <Badge label="In Blueprints ausgeblendet" /> : null}
            {visibleBadges(storageDetail?.badges ?? [], storageDetail?.itemCode).map((badge) => (
              badge === "SCMDB" && scmdbUrl ? (
                <a
                  key={`${storageDetail?.id ?? "item"}-scmdb`}
                  href={scmdbUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="qb-badge qb-badge-highlight"
                >
                  SCMDB
                </a>
              ) : (
                <Badge key={`${storageDetail?.id ?? "item"}-${badge}`} label={badge} />
              )
            ))}
          </div>
        </div>
        <p className="qb-muted">Zentrale Stammdaten fuer Crafting, Lager und Suche.</p>
        {scmdbUrl ? <div className="qb-inline" style={{ marginTop: 8 }}><a href={scmdbUrl} target="_blank" rel="noreferrer" className="qb-nav-link">SCMDB oeffnen</a></div> : null}
        {canEdit && storageDetail ? (
          <form className="qb-form" onSubmit={saveItem}>
            <TextInput value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
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
                        <Button key={badge.name} type="button" variant={selectedBadges.includes(badge.name) ? "primary" : "secondary"} onClick={() => setSelectedBadges((current) => toggleValue(current, badge.name))}>{badge.name}</Button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
            {canAdmin ? <TextInput placeholder="Neue Badges (kommagetrennt)" value={newBadgesInput} onChange={(e) => setNewBadgesInput(e.target.value)} /> : null}
            {canAdmin ? (
              <label className="qb-inline" style={{ gap: 8, alignItems: "center" }}>
                <input type="checkbox" checked={hideFromBlueprints} onChange={(e) => setHideFromBlueprints(e.target.checked)} />
                <span>In Blueprints ausblenden</span>
              </label>
            ) : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Stammdaten speichern"}</Button>
          </form>
        ) : null}
      </Card>

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">Crafting</h2>
          {canEdit ? (
            <Button type="button" variant={amCrafter ? "secondary" : "primary"} onClick={toggleCraftSelf} disabled={busy}>
              {amCrafter ? "Ich kann das nicht mehr craften" : "Ich kann das craften"}
            </Button>
          ) : null}
        </div>
        {!blueprintDetail || blueprintDetail.crafters.length === 0 ? (
          <p className="qb-muted">Noch niemand in der Org kann dieses Item craften.</p>
        ) : (
          <div className="qb-inline" style={{ flexWrap: "wrap" }}>
            {blueprintDetail.crafters.map((crafter) => <Badge key={crafter.userId} label={crafter.username} />)}
          </div>
        )}
      </Card>

      <Card>
        <h2 className="qb-card-title">Lager</h2>
        <p className="qb-muted">Aktuell eingelagert: {totalQty}</p>
        {!storageDetail || storageDetail.entries.length === 0 ? <p className="qb-muted">Noch keine Eintraege vorhanden.</p> : (
          <div className="qb-grid">
            {storageDetail.entries.map((entry) => (
              <Card key={entry.id}>
                <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                  <strong>{entry.username}</strong>
                  <span>{entry.qty}</span>
                </div>
                <div className="qb-muted">{entry.locationLabel}</div>
                {editingEntryId === entry.id ? (
                  <div className="qb-form" style={{ marginTop: 8 }}>
                    <TextInput type="number" min={1} value={editingEntryQty} onChange={(e) => setEditingEntryQty(Number(e.target.value))} required />
                    <TextInput placeholder="Notiz (optional)" value={editingEntryNote} onChange={(e) => setEditingEntryNote(e.target.value)} />
                    <div className="qb-inline">
                      <Button type="button" variant="primary" onClick={() => void saveEntry(entry.id)} disabled={busy}>
                        {busy ? "Speichert..." : "Aenderung speichern"}
                      </Button>
                      <Button
                        type="button"
                        variant="secondary"
                        onClick={() => {
                          setEditingEntryId(null);
                          setEditingEntryQty(1);
                          setEditingEntryNote("");
                        }}
                        disabled={busy}
                      >
                        Bearbeiten beenden
                      </Button>
                    </div>
                  </div>
                ) : entry.note ? <div className="qb-muted">{entry.note}</div> : null}
                {(canAdmin || entry.userId === meUserId) ? (
                  <div className="qb-inline">
                    <Button
                      type="button"
                      variant={editingEntryId === entry.id ? "primary" : "secondary"}
                      onClick={() => {
                        setEditingEntryId(entry.id);
                        setEditingEntryQty(entry.qty);
                        setEditingEntryNote(entry.note ?? "");
                      }}
                      disabled={busy}
                    >
                      Menge aendern
                    </Button>
                    <Button type="button" variant="danger" onClick={() => void deleteEntry(entry.id)} disabled={busy}>Eintrag loeschen</Button>
                  </div>
                ) : null}
              </Card>
            ))}
          </div>
        )}

        {canEdit && storageDetail ? (
          <form className="qb-form" onSubmit={createEntry}>
            {canAdmin ? (
              <SelectInput value={entryUserId} onChange={(e) => setEntryUserId(e.target.value)}>
                {storageDetail.availableUsers.map((user) => <option key={user.userId} value={user.userId}>{user.username}</option>)}
              </SelectInput>
            ) : null}
            <SelectInput value={locationId} onChange={(e) => setLocationId(e.target.value)}>
              {storageDetail.locationFilters.map((location) => <option key={location.id} value={location.id}>{location.label}</option>)}
            </SelectInput>
            <TextInput type="number" min={1} value={qty} onChange={(e) => setQty(Number(e.target.value))} required />
            <TextInput placeholder="Notiz (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Lager-Eintrag speichern"}</Button>
          </form>
        ) : null}
      </Card>

      <Card>
        <h2 className="qb-card-title">Suche</h2>
        {!searchDetail || searchDetail.requests.length === 0 ? (
          <p className="qb-muted">Aktuell sucht noch niemand dieses Item.</p>
        ) : (
          <div className="qb-grid">
            {searchDetail.requests.map((request) => {
              const alreadyOffered = request.offers.some((offer) => offer.userId === meUserId);
              const canOffer = canEdit && request.userId !== meUserId && request.status === "OPEN" && !alreadyOffered;
              const canManageRequest = canAdmin || request.userId === meUserId;

              return (
                <Card key={request.id}>
                  <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12 }}>
                    <strong>{request.username}</strong>
                    <Badge label={request.status === "OPEN" ? "Offen" : request.status === "FULFILLED" ? "Erfuellt" : "Abgebrochen"} />
                  </div>
                  {request.averageQuality ? <div className="qb-muted">Durchschnittsqualitaet: {request.averageQuality}</div> : null}
                  {request.note ? <div className="qb-muted">{request.note}</div> : null}
                  <div className="qb-grid" style={{ gap: 8, marginTop: 8 }}>
                    <strong>Angebote</strong>
                    {request.offers.length === 0 ? (
                      <p className="qb-muted">Noch niemand hat Hilfe angeboten.</p>
                    ) : (
                      request.offers.map((offer) => (
                        <div key={offer.id}>
                          <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                            <span>{offer.username}</span>
                          </div>
                          {offer.note ? <div className="qb-muted">{offer.note}</div> : null}
                        </div>
                      ))
                    )}
                  </div>
                  {canOffer ? (
                    <div className="qb-form" style={{ marginTop: 8 }}>
                      <TextArea
                        rows={2}
                        placeholder="Was kannst du bereitstellen? (optional)"
                        value={offerNotes[request.id] ?? ""}
                        onChange={(e) => setOfferNotes((current) => ({ ...current, [request.id]: e.target.value }))}
                      />
                      <Button type="button" variant="primary" disabled={busy} onClick={() => void createOffer(request.id)}>
                        {busy ? "Speichert..." : "Ich kann etwas bereitstellen"}
                      </Button>
                    </div>
                  ) : null}
                  {canManageRequest ? (
                    <div className="qb-inline" style={{ marginTop: 8 }}>
                      {request.status === "OPEN" ? (
                        <>
                          <Button
                            type="button"
                            variant="primary"
                            disabled={busy}
                            onClick={() => void updateRequestStatus(request.id, "FULFILLED")}
                          >
                            Als erhalten schliessen
                          </Button>
                          <Button
                            type="button"
                            variant="secondary"
                            disabled={busy}
                            onClick={() => void updateRequestStatus(request.id, "CANCELLED")}
                          >
                            Abbrechen
                          </Button>
                        </>
                      ) : null}
                      <Button type="button" variant="danger" disabled={busy} onClick={() => void deleteRequest(request.id)}>
                        Suche loeschen
                      </Button>
                    </div>
                  ) : null}
                </Card>
              );
            })}
          </div>
        )}
        {canEdit ? (
          <form className="qb-form" onSubmit={createRequest}>
            <TextInput placeholder="Average Quality / Durchschnittsqualitaet (optional)" value={averageQuality} onChange={(e) => setAverageQuality(e.target.value)} />
            <TextArea rows={3} placeholder="Notiz (optional)" value={requestNote} onChange={(e) => setRequestNote(e.target.value)} />
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Suche speichern"}</Button>
          </form>
        ) : null}
      </Card>

      <Card>
        <h2 className="qb-card-title">Unterpunkte</h2>
        {!storageDetail || storageDetail.children.length === 0 ? (
          <p className="qb-muted">Noch keine Unterpunkte vorhanden.</p>
        ) : (
          <div className="qb-grid">
            {storageDetail.children.map((child) => (
              <Card key={child.id}>
                <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                  <strong><a href={`/items/${child.id}`}>{child.name}</a></strong>
                  <div className="qb-inline" style={{ gap: 8 }}>
                    {child.hideFromBlueprints ? <Badge label="Ausgeblendet" /> : null}
                    {visibleBadges(child.badges, child.itemCode).map((badge) => {
                      const childScmdbUrl = scmdbUrlForItemCode(child.itemCode);
                      return badge === "SCMDB" && childScmdbUrl ? (
                        <a
                          key={`${child.id}-scmdb`}
                          href={childScmdbUrl}
                          target="_blank"
                          rel="noreferrer"
                          className="qb-badge qb-badge-highlight"
                        >
                          SCMDB
                        </a>
                      ) : (
                        <Badge key={`${child.id}-${badge}`} label={badge} />
                      );
                    })}
                  </div>
                </div>
                <div className="qb-muted">Crafter {child.crafterCount} | Lager {child.totalQty} | Suche {child.openSearchCount}</div>
              </Card>
            ))}
          </div>
        )}
      </Card>

      {canEdit ? (
        <Card>
          <h2 className="qb-card-title">Unterpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createChild}>
            <TextInput placeholder="Name" value={childName} onChange={(e) => setChildName(e.target.value)} required />
            <TextArea rows={3} placeholder="Beschreibung" value={childDescription} onChange={(e) => setChildDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={childItemCode} onChange={(e) => setChildItemCode(e.target.value)} />
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
                        <Button key={badge.name} type="button" variant={childSelectedBadges.includes(badge.name) ? "primary" : "secondary"} onClick={() => setChildSelectedBadges((current) => toggleValue(current, badge.name))}>{badge.name}</Button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
            {canAdmin ? <TextInput placeholder="Neue Badges (kommagetrennt)" value={childNewBadgesInput} onChange={(e) => setChildNewBadgesInput(e.target.value)} /> : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Unterpunkt anlegen"}</Button>
          </form>
        </Card>
      ) : null}

      {canAdmin ? (
        <Card>
          <h2 className="qb-card-title">Admin</h2>
          <form className="qb-form" onSubmit={mergeItems}>
            <strong>Eintraege zusammenfuehren</strong>
            <SelectInput value={mergeTargetId} onChange={(e) => setMergeTargetId(e.target.value)} required>
              <option value="">Zweiten Eintrag auswaehlen</option>
              {allItems.map((item) => (
                <option key={item.id} value={item.id}>{item.name}</option>
              ))}
            </SelectInput>
            <SelectInput value={mergeKeepValuesFrom} onChange={(e) => setMergeKeepValuesFrom(e.target.value as "CURRENT" | "OTHER")}>
              <option value="CURRENT">Titel/Beschreibung/Item-Code von diesem Eintrag behalten</option>
              <option value="OTHER">Titel/Beschreibung/Item-Code vom anderen Eintrag behalten</option>
            </SelectInput>
            <SelectInput value={mergeParentChoice} onChange={(e) => setMergeParentChoice(e.target.value as "CURRENT" | "OTHER" | "ROOT")}>
              <option value="CURRENT">Oberpunkt von diesem Eintrag behalten</option>
              <option value="OTHER">Oberpunkt vom anderen Eintrag behalten</option>
              <option value="ROOT">Kein Oberpunkt</option>
            </SelectInput>
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Fuehrt zusammen..." : "Zusammenfuehren"}
            </Button>
          </form>
          <Button type="button" variant="danger" onClick={deleteItem} disabled={busy}>{busy ? "Loescht..." : "Item komplett loeschen"}</Button>
        </Card>
      ) : null}
    </main>
  );
}
