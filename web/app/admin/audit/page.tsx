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

export default function AdminAuditPage() {
  const [items, setItems] = useState<AuditEvent[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [limit, setLimit] = useState(100);
  const [busy, setBusy] = useState(false);

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
  }, []);

  return (
    <section className="qb-main">
      <h2>Audit Log</h2>
      <Card>
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
          <Button type="button" onClick={refresh} disabled={busy}>Reload</Button>
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
