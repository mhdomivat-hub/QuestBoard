"use client";

import { useEffect, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextInput } from "../../_components/ui/Input";

type AuditEvent = {
  id: string;
  actorUsername: string;
  action: string;
  entityType: string;
  entityId?: string | null;
  details?: string | null;
  createdAt?: string | null;
};

type MeResponse = {
  userId: string;
  username: string;
  role: "guest" | "member" | "admin" | "superAdmin";
};

export default function AdminAuditPage() {
  const [items, setItems] = useState<AuditEvent[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [limit, setLimit] = useState(100);
  const [busy, setBusy] = useState(false);
  const [canClear, setCanClear] = useState(false);
  const [clearBusy, setClearBusy] = useState(false);

  async function refresh() {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/admin/audit/events?limit=${limit}`, { cache: "no-store" });
      if (!res.ok) {
        setError(`Load failed (${res.status})`);
        return;
      }
      setItems(await res.json());
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    refresh();
    fetch("/api/me", { cache: "no-store" })
      .then(async (res) => {
        if (!res.ok) return null;
        return (await res.json()) as MeResponse;
      })
      .then((me) => setCanClear(me?.role === "superAdmin"))
      .catch(() => setCanClear(false));
  }, []);

  async function clearAuditLog() {
    if (!confirm("Audit Log wirklich komplett loeschen? Diese Aktion kann nicht rueckgaengig gemacht werden.")) {
      return;
    }

    setClearBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/admin/audit/events", { method: "DELETE" });
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setError(`Clear failed (${res.status}) ${body}`);
        return;
      }
      setItems([]);
    } finally {
      setClearBusy(false);
    }
  }

  return (
    <section className="qb-main">
      <h2>Audit Log</h2>
      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between", alignItems: "center" }}>
          <div className="qb-inline">
            <label htmlFor="limit">Limit</label>
            <TextInput
              id="limit"
              type="number"
              min={1}
              max={500}
              value={limit}
              onChange={(e) => setLimit(Number(e.target.value))}
            />
            <Button type="button" onClick={refresh} disabled={busy || clearBusy}>Reload</Button>
          </div>
          {canClear ? (
            <Button type="button" variant="danger" onClick={clearAuditLog} disabled={clearBusy || busy}>
              {clearBusy ? "Loesche..." : "Audit Log leeren"}
            </Button>
          ) : null}
        </div>
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}

      <div className="qb-grid">
        {items.map((item) => (
          <Card key={item.id}>
            <div className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong>{item.action}</strong>
              <Badge label={item.entityType} />
            </div>
            <div>actor: {item.actorUsername}</div>
            <div className="qb-muted">entity id: {item.entityId ?? "-"}</div>
            <div className="qb-muted">at: {item.createdAt ?? "-"}</div>
            {item.details ? <div className="qb-muted">details: {item.details}</div> : null}
          </Card>
        ))}
      </div>

      {!error && items.length === 0 ? <p className="qb-muted">No audit events.</p> : null}
    </section>
  );
}
