"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type Crafter = {
  userId: string;
  username: string;
};

type BlueprintChild = {
  id: string;
  name: string;
  itemCode?: string | null;
  badges: string[];
  hideFromBlueprints: boolean;
  isCraftable: boolean;
  childCount: number;
  crafterCount: number;
};

type Breadcrumb = {
  id: string;
  name: string;
};

type BlueprintDetail = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  availableBadges: string[];
  hideFromBlueprints: boolean;
  isCraftable: boolean;
  breadcrumb: Breadcrumb[];
  children: BlueprintChild[];
  crafters: Crafter[];
};

type BlueprintTreeNode = {
  id: string;
  name: string;
  children: BlueprintTreeNode[];
};

type BlueprintListResponse = {
  blueprints: BlueprintTreeNode[];
  availableBadges: string[];
};

function flattenBlueprints(nodes: BlueprintTreeNode[]): Array<{ id: string; name: string }> {
  const result: Array<{ id: string; name: string }> = [];
  const visit = (entries: BlueprintTreeNode[], prefix = "") => {
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

export default function BlueprintDetailPage({ params }: { params: { id: string } }) {
  const [detail, setDetail] = useState<BlueprintDetail | null>(null);
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
  const [allBlueprints, setAllBlueprints] = useState<Array<{ id: string; name: string }>>([]);
  const [mergeTargetId, setMergeTargetId] = useState("");
  const [mergeKeepValuesFrom, setMergeKeepValuesFrom] = useState<"CURRENT" | "OTHER">("CURRENT");
  const [mergeParentChoice, setMergeParentChoice] = useState<"CURRENT" | "OTHER" | "ROOT">("CURRENT");

  const canEdit = role !== null && role !== "guest";
  const canCreateBadges = role === "admin" || role === "superAdmin";
  const canAdmin = role === "admin" || role === "superAdmin";
  const amCrafter = Boolean(detail?.crafters.some((crafter) => crafter.userId === meUserId));
  const scmdbUrl = useMemo(() => (
    detail?.itemCode?.trim() ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(detail.itemCode.trim())}` : null
  ), [detail?.itemCode]);

  async function loadAll() {
    setError(null);
    const requests: Promise<Response>[] = [
      fetch("/api/me", { cache: "no-store" }),
      fetch(`/api/blueprints/${params.id}`, { cache: "no-store" })
    ];
    if (canAdmin) {
      requests.push(fetch("/api/blueprints", { cache: "no-store" }));
    }
    const [meRes, detailRes, listRes] = await Promise.all(requests);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
      setMeUserId((me.userId as string | undefined) ?? null);
    }

    if (!detailRes.ok) {
      setError(`Blueprint load failed (${detailRes.status})`);
      return;
    }

    const body = (await detailRes.json()) as BlueprintDetail;
    setDetail(body);
    setName(body.name);
    setDescription(body.description ?? "");
    setItemCode(body.itemCode ?? "");
    setSelectedBadges(body.badges);
    setHideFromBlueprints(body.hideFromBlueprints);
    setNewBadgesInput("");

    if (listRes?.ok) {
      const listBody = (await listRes.json()) as BlueprintListResponse;
      setAllBlueprints(flattenBlueprints(listBody.blueprints).filter((item) => item.id !== body.id));
    } else {
      setAllBlueprints([]);
    }
  }

  useEffect(() => {
    void loadAll();
  }, [params.id, canAdmin]);

  async function saveBlueprint(e: FormEvent) {
    e.preventDefault();
    if (!detail) return;

    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/blueprints/${params.id}`, {
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
        setError(`Blueprint update failed (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createChild(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/blueprints", {
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
      setChildName("");
      setChildDescription("");
      setChildItemCode("");
      setChildSelectedBadges([]);
      setChildNewBadgesInput("");
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function toggleCraftSelf() {
    if (!detail || !meUserId) return;
    setBusy(true);
    setError(null);
    try {
      const res = amCrafter
        ? await fetch(`/api/blueprints/${detail.id}/crafters/${meUserId}`, { method: "DELETE" })
        : await fetch(`/api/blueprints/${detail.id}/crafters`, {
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

  async function mergeBlueprints(e: FormEvent) {
    e.preventDefault();
    if (!mergeTargetId) {
      setError("Bitte zweiten Eintrag zum Zusammenfuehren auswaehlen.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/blueprints/${params.id}/merge`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          otherBlueprintId: mergeTargetId,
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
        window.location.href = `/blueprints/${merged.id}`;
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function deleteBlueprintEntry() {
    if (!detail) return;
    if (!window.confirm(`Eintrag "${detail.name}" wirklich komplett loeschen? Unterpunkte werden dabei ebenfalls entfernt.`)) {
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/blueprints/${detail.id}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Blueprint loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      window.location.href = "/blueprints";
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="qb-main">
      <h1>Blueprint Detail</h1>
      {detail ? (
        <div className="qb-inline" style={{ marginBottom: 12, flexWrap: "wrap" }}>
          {detail.breadcrumb.map((item, index) => (
            <span key={item.id} className="qb-muted">
              {index > 0 ? " > " : ""}
              <a href={`/blueprints/${item.id}`}>{item.name}</a>
            </span>
          ))}
        </div>
      ) : null}

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">{detail?.name ?? "Blueprint"}</h2>
          {detail ? (
            <div className="qb-inline">
              {detail.hideFromBlueprints ? <Badge label="In Blueprints ausgeblendet" /> : null}
              {detail.badges.map((badge) => <Badge key={badge} label={badge} />)}
            </div>
          ) : null}
        </div>
        {canEdit && detail ? (
          <form className="qb-form" onSubmit={saveBlueprint}>
            <TextInput value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name fuer SCMDB (optional)" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
            <div className="qb-inline" style={{ flexWrap: "wrap" }}>
              {detail.availableBadges.map((badge) => (
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
            {canCreateBadges ? (
              <TextInput placeholder="Neue Badges (kommagetrennt)" value={newBadgesInput} onChange={(e) => setNewBadgesInput(e.target.value)} />
            ) : null}
            {canAdmin ? (
              <label className="qb-inline" style={{ gap: 8, alignItems: "center" }}>
                <input type="checkbox" checked={hideFromBlueprints} onChange={(e) => setHideFromBlueprints(e.target.checked)} />
                <span>In Blueprints ausblenden</span>
              </label>
            ) : null}
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Speichert..." : "Eintrag speichern"}
            </Button>
          </form>
        ) : (
          <div>
            {detail?.description ? <p className="qb-muted">{detail.description}</p> : <p className="qb-muted">Keine Beschreibung.</p>}
          </div>
        )}
        {scmdbUrl ? (
          <div className="qb-inline" style={{ marginTop: 8 }}>
            <a href={scmdbUrl} target="_blank" rel="noreferrer" className="qb-nav-link">SCMDB öffnen</a>
          </div>
        ) : null}
      </Card>

      {detail ? (
        <Card>
          <div className="qb-inline" style={{ justifyContent: "space-between" }}>
            <h2 className="qb-card-title">Crafter</h2>
            {canEdit ? (
              <Button type="button" variant={amCrafter ? "secondary" : "primary"} onClick={toggleCraftSelf} disabled={busy}>
                {amCrafter ? "Ich kann das nicht mehr craften" : "Ich kann das craften"}
              </Button>
            ) : null}
          </div>
          {detail.crafters.length === 0 ? (
            <p className="qb-muted">Noch niemand in der Org kann diesen Eintrag craften.</p>
          ) : (
            <div className="qb-inline" style={{ flexWrap: "wrap" }}>
              {detail.crafters.map((crafter) => (
                <Badge key={crafter.userId} label={crafter.username} />
              ))}
            </div>
          )}
        </Card>
      ) : null}

      {canAdmin && detail ? (
        <Card>
          <h2 className="qb-card-title">Admin</h2>
          <form className="qb-form" onSubmit={mergeBlueprints}>
            <strong>Eintraege zusammenfuehren</strong>
            <SelectInput value={mergeTargetId} onChange={(e) => setMergeTargetId(e.target.value)} required>
              <option value="">Zweiten Eintrag auswaehlen</option>
              {allBlueprints.map((item) => (
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
          <div className="qb-form">
            <strong>Eintrag löschen</strong>
            <p className="qb-muted">Loescht den Eintrag komplett. Unterpunkte werden dabei ebenfalls entfernt.</p>
            <Button type="button" variant="danger" disabled={busy} onClick={deleteBlueprintEntry}>
              {busy ? "Loescht..." : "Eintrag komplett loeschen"}
            </Button>
          </div>
        </Card>
      ) : null}

      <Card>
        <h2 className="qb-card-title">Unterpunkte</h2>
        {detail && detail.children.length === 0 ? <p className="qb-muted">Noch keine Unterpunkte vorhanden.</p> : null}
        <div className="qb-grid">
          {detail?.children.map((child) => (
            <Card key={child.id}>
              <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                <strong><a href={`/blueprints/${child.id}`}>{child.name}</a></strong>
                <div className="qb-inline">
                  {child.hideFromBlueprints ? <Badge label="Ausgeblendet" /> : null}
                  {child.badges.map((badge) => <Badge key={badge} label={badge} />)}
                </div>
              </div>
              <div className="qb-muted">
                {child.childCount} Unterpunkte · {child.crafterCount} Crafter
              </div>
            </Card>
          ))}
        </div>
      </Card>

      {canEdit ? (
        <Card>
          <h2 className="qb-card-title">Unterpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createChild}>
            <TextInput placeholder="Name" value={childName} onChange={(e) => setChildName(e.target.value)} required />
            <TextArea rows={3} placeholder="Beschreibung" value={childDescription} onChange={(e) => setChildDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name fuer SCMDB (optional)" value={childItemCode} onChange={(e) => setChildItemCode(e.target.value)} />
            <div className="qb-inline" style={{ flexWrap: "wrap" }}>
              {detail?.availableBadges.map((badge) => (
                <Button
                  key={badge}
                  type="button"
                  variant={childSelectedBadges.includes(badge) ? "primary" : "secondary"}
                  onClick={() => setChildSelectedBadges((current) => toggleValue(current, badge))}
                >
                  {badge}
                </Button>
              ))}
            </div>
            {canCreateBadges ? (
              <TextInput placeholder="Neue Badges (kommagetrennt)" value={childNewBadgesInput} onChange={(e) => setChildNewBadgesInput(e.target.value)} />
            ) : null}
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Speichert..." : "Unterpunkt anlegen"}
            </Button>
          </form>
        </Card>
      ) : null}
    </main>
  );
}
