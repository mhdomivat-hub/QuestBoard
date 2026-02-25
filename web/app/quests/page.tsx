"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import Badge from "../_components/ui/Badge";
import Card from "../_components/ui/Card";
import { statusLabel } from "../_components/ui/statusLabels";

type QuestStatus = "OPEN" | "IN_PROGRESS" | "DONE" | "ARCHIVED";
type UserRole = "guest" | "member" | "admin" | "superAdmin";

type Quest = {
  id: string;
  title: string;
  description: string;
  status: QuestStatus;
  isApproved: boolean;
  createdAt?: string;
};

function QuestsPageContent() {
  const searchParams = useSearchParams();
  const statusFilter = searchParams.get("status") as QuestStatus | null;
  const [quests, setQuests] = useState<Quest[]>([]);
  const [role, setRole] = useState<UserRole | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function loadQuests() {
    setError(null);
    const res = await fetch("/api/quests", { cache: "no-store" });
    if (!res.ok) {
      setError(`Load failed (${res.status})`);
      return;
    }
    setQuests(await res.json());
  }

  useEffect(() => {
    async function loadAll() {
      const meRes = await fetch("/api/me", { cache: "no-store" });
      if (meRes.ok) {
        const me = await meRes.json();
        setRole((me.role as UserRole | undefined) ?? null);
      }
      await loadQuests();
    }
    loadAll();
  }, []);

  const openCount = quests.filter((q) => q.status === "OPEN").length;
  const inProgressCount = quests.filter((q) => q.status === "IN_PROGRESS").length;
  const doneCount = quests.filter((q) => q.status === "DONE").length;
  const archivedCount = quests.filter((q) => q.status === "ARCHIVED").length;
  const validStatuses: QuestStatus[] = ["OPEN", "IN_PROGRESS", "DONE", "ARCHIVED"];
  const activeFilter = statusFilter && validStatuses.includes(statusFilter) ? statusFilter : null;

  const filteredQuests = useMemo(() => {
    const byFilter = activeFilter ? quests.filter((q) => q.status === activeFilter) : quests;
    const statusOrder: Record<QuestStatus, number> = {
      OPEN: 0,
      IN_PROGRESS: 1,
      DONE: 2,
      ARCHIVED: 3
    };

    return [...byFilter].sort((a, b) => {
      const aPendingOpen = !a.isApproved && a.status === "OPEN";
      const bPendingOpen = !b.isApproved && b.status === "OPEN";
      if (aPendingOpen !== bPendingOpen) return aPendingOpen ? -1 : 1;
      const statusDelta = statusOrder[a.status] - statusOrder[b.status];
      if (statusDelta !== 0) return statusDelta;
      return a.title.localeCompare(b.title);
    });
  }, [quests, activeFilter]);

  return (
    <main className="qb-main">
      <h1>Quests</h1>

      <Card>
        <h2 className="qb-card-title">Dashboard</h2>
        <div className="qb-inline">
          <a href="/quests?status=OPEN"><Badge label={`${statusLabel("OPEN")} ${openCount}`} /></a>
          <a href="/quests?status=IN_PROGRESS"><Badge label={`${statusLabel("IN_PROGRESS")} ${inProgressCount}`} /></a>
          <a href="/quests?status=DONE"><Badge label={`${statusLabel("DONE")} ${doneCount}`} /></a>
          <a href="/quests?status=ARCHIVED"><Badge label={`${statusLabel("ARCHIVED")} ${archivedCount}`} /></a>
          {activeFilter ? <a className="qb-nav-link" href="/quests">Filter zuruecksetzen</a> : null}
        </div>
        {role && role !== "guest" ? (
          <div className="qb-inline" style={{ marginTop: 10 }}>
            <a href="/quests/new">Neue Quest erstellen</a>
          </div>
        ) : null}
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}
      {activeFilter ? <p className="qb-muted">Aktiver Filter: {statusLabel(activeFilter)}</p> : null}

      <section className="qb-grid">
        {filteredQuests.map((q) => (
          <Card key={q.id}>
            <div className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong><a href={`/quests/${q.id}`}>{q.title}</a></strong>
              <div className="qb-inline">
                {!q.isApproved ? <Badge label="PENDING" /> : null}
                <Badge label={q.status} />
              </div>
            </div>
            {!q.isApproved ? <p className="qb-muted">Freigabe ausstehend</p> : null}
            <p className="qb-muted">{q.description}</p>
            <a href={`/quests/${q.id}`}>Details oeffnen</a>
          </Card>
        ))}
        {!error && filteredQuests.length === 0 ? <p className="qb-muted">Keine Quests fuer den gewaehlten Filter.</p> : null}
      </section>
    </main>
  );
}

export default function QuestsPage() {
  return (
    <Suspense fallback={<main className="qb-main"><p className="qb-muted">Lade Quests...</p></main>}>
      <QuestsPageContent />
    </Suspense>
  );
}
