"use client";

import { Suspense, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import Badge from "../_components/ui/Badge";
import Card from "../_components/ui/Card";
import ProgressBar from "../_components/ui/ProgressBar";
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

type RequirementProgress = {
  qtyNeeded: number;
  collectedQty: number;
  deliveredQty: number;
};

type QuestProgress = {
  totalNeeded: number;
  delivered: number;
  collectedPending: number;
};

function QuestsPageContent() {
  const searchParams = useSearchParams();
  const statusFilter = searchParams.get("status") as QuestStatus | null;
  const [quests, setQuests] = useState<Quest[]>([]);
  const [questProgress, setQuestProgress] = useState<Record<string, QuestProgress>>({});
  const [role, setRole] = useState<UserRole | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function loadQuests() {
    setError(null);
    const res = await fetch("/api/quests", { cache: "no-store" });
    if (!res.ok) {
      setError(`Load failed (${res.status})`);
      return;
    }
    const list = (await res.json()) as Quest[];
    setQuests(list);

    const entries = await Promise.all(
      list.map(async (quest) => {
        try {
          const reqRes = await fetch(`/api/quests/${quest.id}/requirements`, { cache: "no-store" });
          if (!reqRes.ok) {
            return [quest.id, { totalNeeded: 0, delivered: 0, collectedPending: 0 }] as const;
          }
          const reqs = (await reqRes.json()) as RequirementProgress[];
          const totalNeeded = reqs.reduce((sum, req) => sum + req.qtyNeeded, 0);
          const delivered = reqs.reduce((sum, req) => sum + Math.min(req.deliveredQty, req.qtyNeeded), 0);
          const collectedPending = reqs.reduce((sum, req) => {
            const cappedDelivered = Math.min(req.deliveredQty, req.qtyNeeded);
            const pending = Math.max(Math.min(req.collectedQty, req.qtyNeeded) - cappedDelivered, 0);
            return sum + pending;
          }, 0);
          return [quest.id, { totalNeeded, delivered, collectedPending }] as const;
        } catch {
          return [quest.id, { totalNeeded: 0, delivered: 0, collectedPending: 0 }] as const;
        }
      })
    );

    setQuestProgress(Object.fromEntries(entries));
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
            {(() => {
              const progress = questProgress[q.id] ?? { totalNeeded: 0, delivered: 0, collectedPending: 0 };
              const hasRequirements = progress.totalNeeded > 0;
              if (!hasRequirements) {
                return <p className="qb-muted">Keine Requirements</p>;
              }
              return (
                <div style={{ marginBottom: 8 }}>
                  <ProgressBar
                    value={progress.delivered}
                    secondaryValue={progress.collectedPending}
                    max={progress.totalNeeded}
                  />
                  <p className="qb-muted">
                    Fortschritt: {progress.delivered}/{progress.totalNeeded} abgegeben |{" "}
                    {progress.collectedPending}/{progress.totalNeeded} gesammelt
                  </p>
                </div>
              );
            })()}
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
