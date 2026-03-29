"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type Person = { userId: string; username: string };
type LocationFilter = { id: string; label: string };
type LocationNode = { id: string; parentId?: string | null; name: string; description?: string | null; children: LocationNode[] };
type Entry = { id: string; userId: string; username: string; locationId: string; locationLabel: string; qty: number; note?: string | null; createdAt?: string | null };
type Child = { id: string; name: string; itemCode?: string | null; badges: string[]; hideFromBlueprints: boolean; totalQty: number; entryCount: number };
type Breadcrumb = { id: string; name: string };
type Detail = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  availableBadges: string[];
  hideFromBlueprints: boolean;
  breadcrumb: Breadcrumb[];
  children: Child[];
  entries: Entry[];
  availableUsers: Person[];
  locations: LocationNode[];
  locationFilters: LocationFilter[];
};

type ItemTreeNode = {
  id: string;
  name: string;
  children: ItemTreeNode[];
};

type ItemListResponse = {
  items: ItemTreeNode[];
};

function flattenItems(nodes: ItemTreeNode[]): Array<{ id: string; name: string }> {
  const result: Array<{ id: string; name: string }> = [];
  const visit = (entries: ItemTreeNode[], prefix = "") => {
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

export default function StorageDetailPage({ params }: { params: { id: string } }) {
  const [detail, setDetail] = useState<Detail | null>(null);
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
  const [editingEntryId, setEditingEntryId] = useState<string | null>(null);
  const [editingEntryQty, setEditingEntryQty] = useState(1);
  const [editingEntryNote, setEditingEntryNote] = useState("");
  const [allItems, setAllItems] = useState<Array<{ id: string; name: string }>>([]);
  const [mergeTargetId, setMergeTargetId] = useState("");
  const [mergeKeepValuesFrom, setMergeKeepValuesFrom] = useState<"CURRENT" | "OTHER">("CURRENT");
  const [mergeParentChoice, setMergeParentChoice] = useState<"CURRENT" | "OTHER" | "ROOT">("CURRENT");

  const canEdit = role !== null && role !== "guest";
  const canAdmin = role === "admin" || role === "superAdmin";
  const scmdbUrl = useMemo(() => (
    detail?.itemCode?.trim() ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(detail.itemCode.trim())}` : null
  ), [detail?.itemCode]);
  const totalQty = useMemo(() => detail?.entries.reduce((sum, entry) => sum + entry.qty, 0) ?? 0, [detail]);

  async function loadAll() {
    setError(null);
    const requests: Promise<Response>[] = [
      fetch("/api/me", { cache: "no-store" }),
      fetch(`/api/storage/items/${params.id}`, { cache: "no-store" })
    ];
    if (canAdmin) {
      requests.push(fetch("/api/storage/items", { cache: "no-store" }));
    }
    const [meRes, detailRes, listRes] = await Promise.all(requests);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
      setMeUserId((me.userId as string | undefined) ?? null);
      setEntryUserId((me.userId as string | undefined) ?? "");
    }

    if (!detailRes.ok) {
      setError(`Item load failed (${detailRes.status})`);
      return;
    }

    const body = (await detailRes.json()) as Detail;
    setDetail(body);
    setName(body.name);
    setDescription(body.description ?? "");
    setItemCode(body.itemCode ?? "");
    setSelectedBadges(body.badges);
    setHideFromBlueprints(body.hideFromBlueprints);
    if (!locationId && body.locationFilters[0]) setLocationId(body.locationFilters[0].id);

    if (listRes?.ok) {
      const listBody = (await listRes.json()) as ItemListResponse;
      setAllItems(flattenItems(listBody.items).filter((item) => item.id !== body.id));
    } else {
      setAllItems([]);
    }
  }

  useEffect(() => {
    void loadAll();
  }, [params.id, canAdmin]);

  async function saveItem(e: FormEvent) {
    e.preventDefault();
    if (!detail) return;
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
          parentId: detail.parentId ?? null,
          hideFromBlueprints
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
      setChildName("");
      setChildDescription("");
      setChildItemCode("");
      setChildSelectedBadges([]);
      setChildNewBadgesInput("");
      await loadAll();
      if (created?.id) window.location.href = `/storage/${created.id}`;
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
      const body = await res.json();
      setDetail(body as Detail);
      setName(body.name);
      setDescription(body.description ?? "");
      setItemCode(body.itemCode ?? "");
      setSelectedBadges(body.badges ?? []);
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
      const body = await res.json();
      setDetail(body as Detail);
      setName(body.name);
      setDescription(body.description ?? "");
      setItemCode(body.itemCode ?? "");
      setSelectedBadges(body.badges ?? []);
      setEditingEntryId(null);
      setEditingEntryQty(1);
      setEditingEntryNote("");
    } finally {
      setBusy(false);
    }
  }

  async function deleteItem() {
    if (!detail || !window.confirm(`Eintrag "${detail.name}" wirklich komplett loeschen?`)) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${detail.id}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      window.location.href = "/storage";
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
        window.location.href = `/storage/${merged.id}`;
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="qb-main">
      <h1>Lager-Detail</h1>
      {detail ? (
        <div className="qb-inline" style={{ marginBottom: 12, flexWrap: "wrap" }}>
          {detail.breadcrumb.map((item, index) => (
            <span key={item.id} className="qb-muted">{index > 0 ? " > " : ""}<a href={`/storage/${item.id}`}>{item.name}</a></span>
          ))}
        </div>
      ) : null}

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">{detail?.name ?? "Item"}</h2>
          <div className="qb-inline">
            {detail?.hideFromBlueprints ? <Badge label="In Blueprints ausgeblendet" /> : null}
            {detail?.badges.map((badge) => <Badge key={badge} label={badge} />)}
          </div>
        </div>
        <p className="qb-muted">Dies sind dieselben Stammdaten wie unter Blueprints. Hier verwaltest du nur den Bestand pro Ort.</p>
        <p className="qb-muted">Aktuell eingelagert: {totalQty}</p>
        {canEdit && detail ? (
          <form className="qb-form" onSubmit={saveItem}>
            <TextInput value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
            <div className="qb-inline">
              {detail.availableBadges.map((badge) => (
                <Button key={badge} type="button" variant={selectedBadges.includes(badge) ? "primary" : "secondary"} onClick={() => setSelectedBadges((current) => toggleValue(current, badge))}>{badge}</Button>
              ))}
            </div>
            {canAdmin ? <TextInput placeholder="Neue Badges (kommagetrennt)" value={newBadgesInput} onChange={(e) => setNewBadgesInput(e.target.value)} /> : null}
            {canAdmin ? (
              <label className="qb-inline" style={{ gap: 8, alignItems: "center" }}>
                <input type="checkbox" checked={hideFromBlueprints} onChange={(e) => setHideFromBlueprints(e.target.checked)} />
                <span>In Blueprints ausblenden</span>
              </label>
            ) : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Item speichern"}</Button>
          </form>
        ) : null}
        {scmdbUrl ? <div className="qb-inline" style={{ marginTop: 8 }}><a href={scmdbUrl} target="_blank" rel="noreferrer" className="qb-nav-link">SCMDB oeffnen</a></div> : null}
      </Card>

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">Lager-Eintraege</h2>
        </div>
        {!detail || detail.entries.length === 0 ? <p className="qb-muted">Noch keine Eintraege vorhanden.</p> : (
          <div className="qb-grid">
            {detail.entries.map((entry) => (
              <Card key={entry.id}>
                <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                  <strong>{entry.username}</strong>
                  <span>{entry.qty}</span>
                </div>
                <div className="qb-muted">{entry.locationLabel}</div>
                {editingEntryId === entry.id ? (
                  <div className="qb-form" style={{ marginTop: 8 }}>
                    <TextInput
                      type="number"
                      min={1}
                      value={editingEntryQty}
                      onChange={(e) => setEditingEntryQty(Number(e.target.value))}
                      required
                    />
                    <TextInput
                      placeholder="Notiz (optional)"
                      value={editingEntryNote}
                      onChange={(e) => setEditingEntryNote(e.target.value)}
                    />
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
      </Card>

      {canEdit && detail ? (
        <Card>
          <h2 className="qb-card-title">Lager-Eintrag anlegen</h2>
          <form className="qb-form" onSubmit={createEntry}>
            {canAdmin ? (
              <SelectInput value={entryUserId} onChange={(e) => setEntryUserId(e.target.value)}>
                {detail.availableUsers.map((user) => <option key={user.userId} value={user.userId}>{user.username}</option>)}
              </SelectInput>
            ) : null}
            <SelectInput value={locationId} onChange={(e) => setLocationId(e.target.value)}>
              {detail.locationFilters.map((location) => <option key={location.id} value={location.id}>{location.label}</option>)}
            </SelectInput>
            <TextInput type="number" min={1} value={qty} onChange={(e) => setQty(Number(e.target.value))} required />
            <TextInput placeholder="Notiz (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Eintrag speichern"}</Button>
          </form>
        </Card>
      ) : null}

      <Card>
        <h2 className="qb-card-title">Unterpunkte</h2>
        {!detail || detail.children.length === 0 ? <p className="qb-muted">Noch keine Unterpunkte vorhanden.</p> : (
          <div className="qb-grid">
            {detail.children.map((child) => (
              <Card key={child.id}>
                <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                  <strong><a href={`/storage/${child.id}`}>{child.name}</a></strong>
                  <div className="qb-inline" style={{ gap: 8 }}>
                    {child.hideFromBlueprints ? <Badge label="Ausgeblendet" /> : null}
                    <span>{child.totalQty}</span>
                  </div>
                </div>
                <div className="qb-inline">{child.badges.map((badge) => <Badge key={badge} label={badge} />)}</div>
                <div className="qb-muted">{child.entryCount} Eintraege</div>
              </Card>
            ))}
          </div>
        )}
      </Card>

      {canEdit && detail ? (
        <Card>
          <h2 className="qb-card-title">Unterpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createChild}>
            <TextInput placeholder="Name" value={childName} onChange={(e) => setChildName(e.target.value)} required />
            <TextArea rows={3} placeholder="Beschreibung" value={childDescription} onChange={(e) => setChildDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={childItemCode} onChange={(e) => setChildItemCode(e.target.value)} />
            <div className="qb-inline">
              {detail.availableBadges.map((badge) => (
                <Button key={badge} type="button" variant={childSelectedBadges.includes(badge) ? "primary" : "secondary"} onClick={() => setChildSelectedBadges((current) => toggleValue(current, badge))}>{badge}</Button>
              ))}
            </div>
            {canAdmin ? <TextInput placeholder="Neue Badges (kommagetrennt)" value={childNewBadgesInput} onChange={(e) => setChildNewBadgesInput(e.target.value)} /> : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Unterpunkt anlegen"}</Button>
          </form>
        </Card>
      ) : null}

      {canAdmin && detail ? (
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
