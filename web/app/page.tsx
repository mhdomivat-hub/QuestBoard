"use client";

import { useEffect, useMemo, useState } from "react";
import Badge from "./_components/ui/Badge";
import Card from "./_components/ui/Card";
import { statusLabel } from "./_components/ui/statusLabels";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type QuestStatus = "OPEN" | "IN_PROGRESS" | "DONE" | "ARCHIVED";

type MeResponse = {
  userId: string;
  username: string;
  role: UserRole;
};

type Quest = {
  id: string;
  title: string;
  description?: string;
  status: QuestStatus;
  createdAt?: string;
};

export default function HomePage() {
  const [me, setMe] = useState<MeResponse | null>(null);
  const [quests, setQuests] = useState<Quest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const [meRes, questRes] = await Promise.all([
          fetch("/api/me", { cache: "no-store" }),
          fetch("/api/quests", { cache: "no-store" })
        ]);

        if (!meRes.ok) {
          setError(`User load failed (${meRes.status})`);
          return;
        }
        if (!questRes.ok) {
          setError(`Quest load failed (${questRes.status})`);
          return;
        }

        setMe((await meRes.json()) as MeResponse);
        setQuests((await questRes.json()) as Quest[]);
      } catch {
        setError("Dashboard load failed");
      } finally {
        setLoading(false);
      }
    }
    load();
  }, []);

  const canAdmin = me?.role === "admin" || me?.role === "superAdmin";

  const stats = useMemo(() => {
    return {
      total: quests.length,
      open: quests.filter((q) => q.status === "OPEN").length,
      inProgress: quests.filter((q) => q.status === "IN_PROGRESS").length,
      done: quests.filter((q) => q.status === "DONE").length,
      archived: quests.filter((q) => q.status === "ARCHIVED").length
    };
  }, [quests]);

  const recentQuests = useMemo(() => {
    return [...quests]
      .filter((q) => q.status !== "DONE" && q.status !== "ARCHIVED")
      .sort((a, b) => {
        const aTime = a.createdAt ? Date.parse(a.createdAt) : 0;
        const bTime = b.createdAt ? Date.parse(b.createdAt) : 0;
        return bTime - aTime;
      })
      .slice(0, 5);
  }, [quests]);

  return (
    <main className="qb-main">
      <h1>QuestBoard Zentrale</h1>
      <p className="qb-muted">Star Citizen Org Control Panel</p>

      {loading ? <p className="qb-muted">Lade Dashboard...</p> : null}
      {error ? <p className="qb-error">{error}</p> : null}

      {!loading && !error ? (
        <>
          <Card>
            <h2 className="qb-card-title">Operator</h2>
            <div className="qb-inline">
              <strong>{me?.username}</strong>
              <Badge label={me?.role ?? "member"} />
            </div>
          </Card>

          <section className="qb-grid two">
            <Card>
              <h3 className="qb-card-title">Quest Lage</h3>
              <div className="qb-grid">
                <a className="qb-nav-link" href="/quests">Gesamt: {stats.total}</a>
                <a className="qb-nav-link" href="/quests?status=OPEN">{statusLabel("OPEN")}: {stats.open}</a>
                <a className="qb-nav-link" href="/quests?status=IN_PROGRESS">{statusLabel("IN_PROGRESS")}: {stats.inProgress}</a>
                <a className="qb-nav-link" href="/quests?status=DONE">{statusLabel("DONE")}: {stats.done}</a>
                <a className="qb-nav-link" href="/quests?status=ARCHIVED">{statusLabel("ARCHIVED")}: {stats.archived}</a>
              </div>
            </Card>

            <Card>
              <h3 className="qb-card-title">Quick Actions</h3>
              <div className="qb-grid">
                <a className="qb-nav-link" href="/quests">Quest Uebersicht</a>
                {canAdmin ? <a className="qb-nav-link" href="/quests/new">Neue Quest erstellen</a> : null}
                {canAdmin ? <a className="qb-nav-link" href="/admin/quest-templates">Admin: Quest Templates</a> : null}
                {canAdmin ? <a className="qb-nav-link" href="/admin/retention">Admin: Retention</a> : null}
                {canAdmin ? <a className="qb-nav-link" href="/admin/audit">Admin: Audit Log</a> : null}
              </div>
            </Card>
          </section>

          <Card>
            <h3 className="qb-card-title">Neueste Quests</h3>
            {recentQuests.length === 0 ? (
              <p className="qb-muted">Noch keine Quests vorhanden.</p>
            ) : (
              <div className="qb-grid">
                {recentQuests.map((quest) => (
                  <div key={quest.id} className="qb-inline" style={{ justifyContent: "space-between" }}>
                    <div>
                      <strong><a href={`/quests/${quest.id}`}>{quest.title}</a></strong>
                      <div className="qb-muted" style={{ fontSize: 12 }}>
                        {quest.createdAt ? new Date(quest.createdAt).toLocaleString("de-DE") : "ohne Datum"}
                      </div>
                    </div>
                    <Badge label={quest.status} />
                  </div>
                ))}
              </div>
            )}
          </Card>
        </>
      ) : null}
    </main>
  );
}
