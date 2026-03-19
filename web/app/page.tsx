"use client";

import { useEffect, useMemo, useState } from "react";
import Badge from "./_components/ui/Badge";
import Card from "./_components/ui/Card";
import ProgressWithLegend from "./_components/ui/ProgressWithLegend";
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
  isApproved?: boolean;
  isPrioritized?: boolean;
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

type BlueprintNode = {
  id: string;
  name: string;
  createdAt?: string | null;
  latestActivityAt?: string | null;
  badges: string[];
  children: BlueprintNode[];
};

type StorageNode = {
  id: string;
  name: string;
  createdAt?: string | null;
  latestActivityAt?: string | null;
  badges: string[];
  totalQty: number;
  children: StorageNode[];
};

type BlueprintListResponse = {
  blueprints: BlueprintNode[];
};

type StorageListResponse = {
  items: StorageNode[];
};

function flattenBlueprints(nodes: BlueprintNode[]): BlueprintNode[] {
  return nodes.flatMap((node) => [node, ...flattenBlueprints(node.children)]);
}

function flattenStorage(nodes: StorageNode[]): StorageNode[] {
  return nodes.flatMap((node) => [node, ...flattenStorage(node.children)]);
}

export default function HomePage() {
  const [me, setMe] = useState<MeResponse | null>(null);
  const [quests, setQuests] = useState<Quest[]>([]);
  const [questProgress, setQuestProgress] = useState<Record<string, QuestProgress>>({});
  const [blueprints, setBlueprints] = useState<BlueprintNode[]>([]);
  const [storageItems, setStorageItems] = useState<StorageNode[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const [meRes, questRes, blueprintRes, storageRes] = await Promise.all([
          fetch("/api/me", { cache: "no-store" }),
          fetch("/api/quests", { cache: "no-store" }),
          fetch("/api/blueprints", { cache: "no-store" }),
          fetch("/api/storage/items", { cache: "no-store" })
        ]);

        if (!meRes.ok) {
          setError(`User load failed (${meRes.status})`);
          return;
        }
        if (!questRes.ok) {
          setError(`Quest load failed (${questRes.status})`);
          return;
        }
        if (!blueprintRes.ok) {
          setError(`Blueprint load failed (${blueprintRes.status})`);
          return;
        }
        if (!storageRes.ok) {
          setError(`Storage load failed (${storageRes.status})`);
          return;
        }

        setMe((await meRes.json()) as MeResponse);
        const questData = (await questRes.json()) as Quest[];
        setQuests(questData);
        setBlueprints(((await blueprintRes.json()) as BlueprintListResponse).blueprints ?? []);
        setStorageItems(((await storageRes.json()) as StorageListResponse).items ?? []);

        const progressEntries = await Promise.all(
          questData.map(async (quest) => {
            try {
              const response = await fetch(`/api/quests/${quest.id}/requirements`, { cache: "no-store" });
              if (!response.ok) {
                return [quest.id, { totalNeeded: 0, delivered: 0, collectedPending: 0 }] as const;
              }

              const requirements = (await response.json()) as RequirementProgress[];
              const totalNeeded = requirements.reduce((sum, requirement) => sum + requirement.qtyNeeded, 0);
              const delivered = requirements.reduce(
                (sum, requirement) => sum + Math.min(requirement.deliveredQty, requirement.qtyNeeded),
                0
              );
              const collectedPending = requirements.reduce((sum, requirement) => {
                const deliveredCapped = Math.min(requirement.deliveredQty, requirement.qtyNeeded);
                const remainingAfterDelivered = Math.max(requirement.qtyNeeded - deliveredCapped, 0);
                return sum + Math.min(requirement.collectedQty, remainingAfterDelivered);
              }, 0);

              return [quest.id, { totalNeeded, delivered, collectedPending }] as const;
            } catch {
              return [quest.id, { totalNeeded: 0, delivered: 0, collectedPending: 0 }] as const;
            }
          })
        );

        setQuestProgress(Object.fromEntries(progressEntries));
      } catch {
        setError("Dashboard load failed");
      } finally {
        setLoading(false);
      }
    }
    load();
  }, []);

  const recentQuests = useMemo(() => {
    return [...quests]
      .filter((q) => q.status !== "DONE" && q.status !== "ARCHIVED")
      .sort((a, b) => {
        const aPriority = !!a.isPrioritized && !!a.isApproved;
        const bPriority = !!b.isPrioritized && !!b.isApproved;
        if (aPriority !== bPriority) return aPriority ? -1 : 1;
        const aTime = a.createdAt ? Date.parse(a.createdAt) : 0;
        const bTime = b.createdAt ? Date.parse(b.createdAt) : 0;
        return bTime - aTime;
      })
      .slice(0, 5);
  }, [quests]);

  const latestBlueprints = useMemo(() => {
    return flattenBlueprints(blueprints)
      .sort((a, b) => {
        const aTime = Date.parse(a.latestActivityAt ?? a.createdAt ?? "") || 0;
        const bTime = Date.parse(b.latestActivityAt ?? b.createdAt ?? "") || 0;
        return bTime - aTime;
      })
      .slice(0, 5);
  }, [blueprints]);

  const latestStorageItems = useMemo(() => {
    return flattenStorage(storageItems)
      .sort((a, b) => {
        const aTime = Date.parse(a.latestActivityAt ?? a.createdAt ?? "") || 0;
        const bTime = Date.parse(b.latestActivityAt ?? b.createdAt ?? "") || 0;
        return bTime - aTime;
      })
      .slice(0, 5);
  }, [storageItems]);

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

          <Card>
            <h3 className="qb-card-title">Neueste Quests</h3>
            {recentQuests.length === 0 ? (
              <p className="qb-muted">Noch keine Quests vorhanden.</p>
            ) : (
              <div className="qb-grid">
                {recentQuests.map((quest) => (
                  <div key={quest.id} className="qb-grid" style={{ gap: 10 }}>
                    <div className="qb-inline" style={{ justifyContent: "space-between", alignItems: "flex-start" }}>
                      <div>
                        <strong><a href={`/quests/${quest.id}`}>{quest.title}</a></strong>
                        <div className="qb-muted" style={{ fontSize: 12 }}>
                          {quest.createdAt ? new Date(quest.createdAt).toLocaleString("de-DE") : "ohne Datum"}
                        </div>
                      </div>
                      <div className="qb-inline">
                        {quest.isPrioritized ? <Badge label="PRIORITAET" /> : null}
                        <Badge label={statusLabel(quest.status)} />
                      </div>
                    </div>
                    {(questProgress[quest.id]?.totalNeeded ?? 0) > 0 ? (
                      <ProgressWithLegend
                        delivered={questProgress[quest.id].delivered}
                        collectedPending={questProgress[quest.id].collectedPending}
                        remaining={Math.max(
                          questProgress[quest.id].totalNeeded -
                            questProgress[quest.id].delivered -
                            questProgress[quest.id].collectedPending,
                          0
                        )}
                        max={questProgress[quest.id].totalNeeded}
                      />
                    ) : null}
                  </div>
                ))}
              </div>
            )}
          </Card>

          <section className="qb-grid two">
            <Card>
              <h3 className="qb-card-title">Zuletzt aktive Blueprints</h3>
              {latestBlueprints.length === 0 ? (
                <p className="qb-muted">Noch keine Blueprints vorhanden.</p>
              ) : (
                <div className="qb-grid">
                  {latestBlueprints.map((blueprint) => (
                    <div key={blueprint.id} className="qb-inline" style={{ justifyContent: "space-between" }}>
                      <div>
                        <strong><a href={`/blueprints/${blueprint.id}`}>{blueprint.name}</a></strong>
                        <div className="qb-muted" style={{ fontSize: 12 }}>
                          {blueprint.latestActivityAt || blueprint.createdAt
                            ? `Letzte Aktivitaet ${new Date(
                                blueprint.latestActivityAt ?? blueprint.createdAt ?? ""
                              ).toLocaleString("de-DE")}`
                            : "ohne Aktivitaet"}
                        </div>
                      </div>
                      <div className="qb-inline">
                        {blueprint.badges.slice(0, 2).map((badge) => <Badge key={`${blueprint.id}-${badge}`} label={badge} />)}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Card>

            <Card>
              <h3 className="qb-card-title">Zuletzt aktive Lager-Eintraege</h3>
              {latestStorageItems.length === 0 ? (
                <p className="qb-muted">Noch keine Lager-Eintraege vorhanden.</p>
              ) : (
                <div className="qb-grid">
                  {latestStorageItems.map((item) => (
                    <div key={item.id} className="qb-inline" style={{ justifyContent: "space-between" }}>
                      <div>
                        <strong><a href={`/storage/${item.id}`}>{item.name}</a></strong>
                        <div className="qb-muted" style={{ fontSize: 12 }}>
                          {item.latestActivityAt || item.createdAt
                            ? `Letzte Aktivitaet ${new Date(
                                item.latestActivityAt ?? item.createdAt ?? ""
                              ).toLocaleString("de-DE")}`
                            : "ohne Aktivitaet"}
                        </div>
                      </div>
                      <div className="qb-inline">
                        <span className="qb-muted">{item.totalQty} im Lager</span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </Card>
          </section>
        </>
      ) : null}
    </main>
  );
}
