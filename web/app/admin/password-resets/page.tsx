"use client";

import { useEffect, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";

type PendingReset = {
  id: string;
  username: string;
  status: "PENDING" | "APPROVED" | "COMPLETED" | "REJECTED";
  createdAt?: string | null;
  note?: string | null;
};

export default function AdminPasswordResetsPage() {
  const [items, setItems] = useState<PendingReset[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [lastLink, setLastLink] = useState<string | null>(null);

  async function refresh() {
    setError(null);
    const res = await fetch("/api/admin/password-resets/pending", { cache: "no-store" });
    if (!res.ok) {
      setError(`Load failed (${res.status})`);
      return;
    }
    setItems(await res.json());
  }

  useEffect(() => {
    refresh();
  }, []);

  async function approve(id: string) {
    setError(null);
    setLastLink(null);
    const res = await fetch(`/api/admin/password-resets/${id}/approve`, { method: "POST" });
    if (!res.ok) {
      setError(`Approve failed (${res.status})`);
      return;
    }
    const body = await res.json();
    setLastLink(body.resetLink ?? null);
    await refresh();
  }

  async function reject(id: string) {
    setError(null);
    const res = await fetch(`/api/admin/password-resets/${id}/reject`, { method: "POST" });
    if (!res.ok) {
      setError(`Reject failed (${res.status})`);
      return;
    }
    await refresh();
  }

  return (
    <section className="qb-main">
      <h2>Password Resets</h2>
      {lastLink ? <Card><code>{lastLink}</code></Card> : null}
      {error ? <p className="qb-error">{error}</p> : null}

      <div className="qb-grid">
        {items.map((item) => (
          <Card key={item.id}>
            <div className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong>{item.username}</strong>
              <Badge label={item.status} />
            </div>
            <div className="qb-muted">{item.createdAt ?? ""}</div>
            {item.note ? <div className="qb-muted">Note: {item.note}</div> : null}
            <div className="qb-inline">
              <Button variant="primary" onClick={() => approve(item.id)}>Approve</Button>
              <Button variant="danger" onClick={() => reject(item.id)}>Reject</Button>
            </div>
          </Card>
        ))}
      </div>

      {items.length === 0 ? <p className="qb-muted">Keine offenen Requests.</p> : null}
    </section>
  );
}
