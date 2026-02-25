"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextInput } from "../../_components/ui/Input";

type InviteRole = "guest" | "member" | "admin" | "superAdmin";
type InviteItem = {
  id: string;
  role: InviteRole;
  status: "OPEN" | "USED" | "EXPIRED" | "REVOKED";
  token?: string | null;
  inviteLink?: string | null;
  maxUses: number;
  useCount: number;
  remainingUses: number;
  expiresAt: string;
  createdAt: string;
  usedAt?: string | null;
  revokedAt?: string | null;
  createdByUsername: string;
};

type CreateInviteResponse = {
  invite: InviteItem;
  token: string;
  inviteLink: string;
};

export default function AdminInvitesPage() {
  const [items, setItems] = useState<InviteItem[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [expiresInHours, setExpiresInHours] = useState("168");
  const [maxUses, setMaxUses] = useState("1");
  const [lastInviteLink, setLastInviteLink] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [showClosedInvites, setShowClosedInvites] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  async function refresh() {
    setError(null);
    const res = await fetch("/api/admin/invites", { cache: "no-store" });
    if (!res.ok) {
      setError(`Invites load failed (${res.status})`);
      return;
    }
    setItems(await res.json());
  }

  useEffect(() => {
    refresh();
  }, []);

  async function createInvite(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    setLastInviteLink(null);
    try {
      const hours = Number(expiresInHours);
      const uses = Number(maxUses);
      if (!Number.isFinite(hours) || hours < 1) {
        setError("Ungueltige Ablaufzeit");
        return;
      }
      if (!Number.isFinite(uses) || uses < 1) {
        setError("Ungueltige Anzahl Nutzungen");
        return;
      }

      const res = await fetch("/api/admin/invites", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ expiresInHours: Math.floor(hours), maxUses: Math.floor(uses) })
      });
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setError(`Invite create failed (${res.status}) ${body}`);
        return;
      }
      const data = (await res.json()) as CreateInviteResponse;
      setLastInviteLink(data.inviteLink);
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  async function revokeInvite(id: string) {
    setError(null);
    const res = await fetch(`/api/admin/invites/${id}/revoke`, { method: "PATCH" });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      setError(`Revoke failed (${res.status}) ${body}`);
      return;
    }
    await refresh();
  }

  async function copyText(value: string, successMessage: string) {
    try {
      await navigator.clipboard.writeText(value);
      setNotice(successMessage);
      setTimeout(() => setNotice(null), 1600);
    } catch {
      setError("Kopieren fehlgeschlagen (Clipboard nicht verfuegbar)");
    }
  }

  const visibleItems = useMemo(() => {
    if (showClosedInvites) return items;
    return items.filter((item) => item.status === "OPEN");
  }, [items, showClosedInvites]);

  return (
    <section className="qb-main">
      <h2>Invites</h2>

      <Card>
        <form className="qb-form" onSubmit={createInvite}>
          <p className="qb-muted">Rolle: guest (read-only)</p>
          <TextInput
            type="number"
            min={1}
            max={720}
            value={expiresInHours}
            onChange={(e) => setExpiresInHours(e.target.value)}
            placeholder="Ablauf in Stunden"
            disabled={busy}
          />
          <TextInput
            type="number"
            min={1}
            max={10000}
            value={maxUses}
            onChange={(e) => setMaxUses(e.target.value)}
            placeholder="Nutzungen"
            disabled={busy}
          />
          <Button type="submit" variant="primary" disabled={busy}>
            {busy ? "Erstelle..." : "Invite erstellen"}
          </Button>
        </form>
        {lastInviteLink ? (
          <div>
            <p className="qb-muted">Invite-Link:</p>
            <code>{lastInviteLink}</code>
          </div>
        ) : null}
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}
      {notice ? <p className="qb-muted">{notice}</p> : null}

      <div className="qb-inline" style={{ justifyContent: "space-between" }}>
        <p className="qb-muted">
          {showClosedInvites
            ? `Zeige alle Invites (${items.length})`
            : `Zeige nur offene Invites (${visibleItems.length})`}
        </p>
        <Button variant="secondary" onClick={() => setShowClosedInvites((prev) => !prev)}>
          {showClosedInvites ? "Verbrauchte ausblenden" : "Verbrauchte einblenden"}
        </Button>
      </div>

      <div className="qb-grid">
        {visibleItems.map((item) => (
          <Card key={item.id}>
            <div className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong>{item.role}</strong>
              <Badge label={item.status} />
            </div>
            <p className="qb-muted">Erstellt von: {item.createdByUsername}</p>
            <p className="qb-muted">Erstellt: {item.createdAt}</p>
            <p className="qb-muted">Ablauf: {item.expiresAt}</p>
            <p className="qb-muted">
              Nutzungen: {item.useCount}/{item.maxUses} (offen: {item.remainingUses})
            </p>
            {item.usedAt ? <p className="qb-muted">Benutzt: {item.usedAt}</p> : null}
            {item.revokedAt ? <p className="qb-muted">Widerrufen: {item.revokedAt}</p> : null}
            <div className="qb-inline">
              <Button
                variant="secondary"
                disabled={!item.inviteLink}
                onClick={() => item.inviteLink && copyText(item.inviteLink, "Invite-Link kopiert")}
              >
                Link kopieren
              </Button>
              <Button
                variant="secondary"
                disabled={!item.token}
                onClick={() => item.token && copyText(item.token, "Invite-Code kopiert")}
              >
                Code kopieren
              </Button>
            </div>
            {item.status === "OPEN" ? (
              <Button variant="danger" onClick={() => revokeInvite(item.id)}>
                Invite widerrufen
              </Button>
            ) : null}
          </Card>
        ))}
      </div>
    </section>
  );
}
