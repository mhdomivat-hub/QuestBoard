"use client";

import { FormEvent, useEffect, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextArea, TextInput } from "../../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type Crafter = {
  userId: string;
  username: string;
};

type BlueprintChild = {
  id: string;
  name: string;
  badges: string[];
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
  badges: string[];
  availableBadges: string[];
  isCraftable: boolean;
  breadcrumb: Breadcrumb[];
  children: BlueprintChild[];
  crafters: Crafter[];
};

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
  const [selectedBadges, setSelectedBadges] = useState<string[]>([]);
  const [newBadgesInput, setNewBadgesInput] = useState("");

  const [childName, setChildName] = useState("");
  const [childDescription, setChildDescription] = useState("");
  const [childSelectedBadges, setChildSelectedBadges] = useState<string[]>([]);
  const [childNewBadgesInput, setChildNewBadgesInput] = useState("");

  const canEdit = role !== null && role !== "guest";
  const canCreateBadges = role === "admin" || role === "superAdmin";
  const amCrafter = Boolean(detail?.crafters.some((crafter) => crafter.userId === meUserId));

  async function loadAll() {
    setError(null);
    const [meRes, detailRes] = await Promise.all([
      fetch("/api/me", { cache: "no-store" }),
      fetch(`/api/blueprints/${params.id}`, { cache: "no-store" })
    ]);

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
    setSelectedBadges(body.badges);
    setNewBadgesInput("");
  }

  useEffect(() => {
    void loadAll();
  }, [params.id]);

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
          badges: [...selectedBadges, ...parseBadges(newBadgesInput)],
          parentId: detail.parentId ?? null
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
              {detail.badges.map((badge) => <Badge key={badge} label={badge} />)}
            </div>
          ) : null}
        </div>
        {canEdit && detail ? (
          <form className="qb-form" onSubmit={saveBlueprint}>
            <TextInput value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
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
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Speichert..." : "Eintrag speichern"}
            </Button>
          </form>
        ) : (
          <div>
            {detail?.description ? <p className="qb-muted">{detail.description}</p> : <p className="qb-muted">Keine Beschreibung.</p>}
          </div>
        )}
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

      <Card>
        <h2 className="qb-card-title">Unterpunkte</h2>
        {detail && detail.children.length === 0 ? <p className="qb-muted">Noch keine Unterpunkte vorhanden.</p> : null}
        <div className="qb-grid">
          {detail?.children.map((child) => (
            <Card key={child.id}>
              <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                <strong><a href={`/blueprints/${child.id}`}>{child.name}</a></strong>
                <div className="qb-inline">
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
