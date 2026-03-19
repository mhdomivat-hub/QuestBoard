"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { useParams } from "next/navigation";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../../_components/ui/Input";
import ProgressWithLegend from "../../_components/ui/ProgressWithLegend";
import { statusLabel } from "../../_components/ui/statusLabels";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type QuestStatus = "OPEN" | "IN_PROGRESS" | "DONE" | "ARCHIVED";
type ContributionStatus = "CLAIMED" | "COLLECTED" | "DELIVERED" | "CANCELLED";

type Quest = {
  id: string;
  title: string;
  description: string;
  handoverInfo?: string | null;
  status: QuestStatus;
  createdByUserId?: string | null;
  createdByUsername?: string | null;
  isApproved: boolean;
  approvedAt?: string | null;
  isPrioritized: boolean;
};

type Requirement = {
  id: string;
  questId: string;
  itemName: string;
  qtyNeeded: number;
  unit: string;
  collectedQty: number;
  deliveredQty: number;
  openQty: number;
  excessQty: number;
};

type Contribution = {
  id: string;
  requirementId: string;
  userId: string;
  username: string;
  qty: number;
  status: ContributionStatus;
  note?: string | null;
};

const contributionStatuses: ContributionStatus[] = ["CLAIMED", "COLLECTED", "DELIVERED", "CANCELLED"];
const questStatuses: QuestStatus[] = ["OPEN", "IN_PROGRESS", "DONE", "ARCHIVED"];

export default function QuestDetailPage() {
  const routeParams = useParams<{ id: string }>();
  const questId = routeParams.id;

  const [quest, setQuest] = useState<Quest | null>(null);
  const [requirements, setRequirements] = useState<Requirement[]>([]);
  const [contributions, setContributions] = useState<Record<string, Contribution[]>>({});
  const [error, setError] = useState<string | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [currentUserRole, setCurrentUserRole] = useState<UserRole | null>(null);
  const [editMode, setEditMode] = useState(false);
  const [editTitle, setEditTitle] = useState("");
  const [editDescription, setEditDescription] = useState("");
  const [editHandoverInfo, setEditHandoverInfo] = useState("");
  const [editIsPrioritized, setEditIsPrioritized] = useState(false);
  const [savingQuestDetails, setSavingQuestDetails] = useState(false);

  const [newReqItem, setNewReqItem] = useState("");
  const [newReqQty, setNewReqQty] = useState(1);
  const [newReqUnit, setNewReqUnit] = useState("pcs");

  const [newContribQty, setNewContribQty] = useState<Record<string, number>>({});
  const [newContribStatus, setNewContribStatus] = useState<Record<string, ContributionStatus>>({});
  const [newContribNote, setNewContribNote] = useState<Record<string, string>>({});
  const [expandedContributions, setExpandedContributions] = useState<Record<string, boolean>>({});
  const [editingContribution, setEditingContribution] = useState<Record<string, boolean>>({});
  const [editContribQty, setEditContribQty] = useState<Record<string, number>>({});
  const [editContribNote, setEditContribNote] = useState<Record<string, string>>({});

  async function loadQuest() {
    const res = await fetch(`/api/quests/${questId}`, { cache: "no-store" });
    if (!res.ok) throw new Error(`Quest load failed (${res.status})`);
    const loaded = (await res.json()) as Quest;
    setQuest(loaded);
    setEditTitle(loaded.title ?? "");
    setEditDescription(loaded.description ?? "");
    setEditHandoverInfo(loaded.handoverInfo ?? "");
    setEditIsPrioritized(loaded.isPrioritized ?? false);
  }

  async function loadMe() {
    const res = await fetch("/api/me", { cache: "no-store" });
    if (!res.ok) throw new Error(`User load failed (${res.status})`);
    const me = await res.json();
    setCurrentUserId((me.userId as string | undefined) ?? null);
    setCurrentUserRole((me.role as UserRole | undefined) ?? null);
  }

  async function loadRequirements() {
    const res = await fetch(`/api/quests/${questId}/requirements`, { cache: "no-store" });
    if (!res.ok) throw new Error(`Requirements load failed (${res.status})`);
    const data = (await res.json()) as Requirement[];
    setRequirements(data);

    for (const req of data) {
      await loadContributions(req.id);
    }
  }

  async function loadContributions(requirementId: string) {
    const res = await fetch(`/api/requirements/${requirementId}/contributions`, { cache: "no-store" });
    if (!res.ok) throw new Error(`Contributions load failed (${res.status})`);
    const data = (await res.json()) as Contribution[];
    setContributions((prev) => ({ ...prev, [requirementId]: data }));
  }

  async function refreshAll() {
    setError(null);
    try {
      await Promise.all([loadMe(), loadQuest()]);
      await loadRequirements();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error");
    }
  }

  useEffect(() => {
    if (!questId) return;
    refreshAll();
  }, [questId]);

  async function createRequirement(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!canEditQuest) {
      setError("Requirement-Erstellung hier nicht erlaubt.");
      return;
    }

    const res = await fetch(`/api/quests/${questId}/requirements`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ itemName: newReqItem, qtyNeeded: newReqQty, unit: newReqUnit })
    });

    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Create requirement failed (${res.status}) ${txt}`);
      return;
    }

    setNewReqItem("");
    setNewReqQty(1);
    setNewReqUnit("pcs");
    await refreshAll();
  }

  async function createContribution(requirementId: string, e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (currentUserRole === "guest") {
      setError("Gast-Accounts sind read-only.");
      return;
    }

    const qty = newContribQty[requirementId] ?? 1;
    const status = newContribStatus[requirementId] ?? "CLAIMED";
    const note = newContribNote[requirementId] ?? "";

    const res = await fetch(`/api/requirements/${requirementId}/contributions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ qty, status, note: note || null })
    });

    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Create contribution failed (${res.status}) ${txt}`);
      return;
    }

    setNewContribQty((p) => ({ ...p, [requirementId]: 1 }));
    setNewContribStatus((p) => ({ ...p, [requirementId]: "CLAIMED" }));
    setNewContribNote((p) => ({ ...p, [requirementId]: "" }));
    await refreshAll();
  }

  async function updateContributionStatus(contributionId: string, status: ContributionStatus) {
    setError(null);

    const res = await fetch(`/api/contributions/${contributionId}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status })
    });

    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Update contribution failed (${res.status}) ${txt}`);
      return;
    }

    await refreshAll();
  }

  async function updateContribution(contributionId: string, qty: number, note: string) {
    setError(null);

    const res = await fetch(`/api/contributions/${contributionId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ qty, note: note || null })
    });

    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Contribution bearbeiten fehlgeschlagen (${res.status}) ${txt}`);
      return;
    }

    setEditingContribution((prev) => ({ ...prev, [contributionId]: false }));
    await refreshAll();
  }

  async function updateQuestStatus(status: QuestStatus) {
    setError(null);
    const canAdmin = currentUserRole === "admin" || currentUserRole === "superAdmin";
    if (!canAdmin) {
      setError("Forbidden (admin only)");
      return;
    }

    const res = await fetch(`/api/quests/${questId}/status`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status })
    });

    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Update quest failed (${res.status}) ${txt}`);
      return;
    }

    await refreshAll();
  }

  async function approveQuest() {
    setError(null);
    const res = await fetch(`/api/quests/${questId}/approve`, {
      method: "POST"
    });
    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Quest freigeben fehlgeschlagen (${res.status}) ${txt}`);
      return;
    }
    await refreshAll();
  }

  async function updateQuestDetails(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSavingQuestDetails(true);
    try {
      const res = await fetch(`/api/quests/${questId}`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          title: editTitle,
          description: editDescription,
          handoverInfo: editHandoverInfo || null,
          isPrioritized: canAdmin ? editIsPrioritized : undefined
        })
      });
      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        setError(`Quest-Details speichern fehlgeschlagen (${res.status}) ${txt}`);
        return;
      }
      await refreshAll();
    } finally {
      setSavingQuestDetails(false);
    }
  }

  async function createTemplateFromQuest() {
    setError(null);
    const res = await fetch(`/api/quests/${questId}/template`, {
      method: "POST"
    });
    if (!res.ok) {
      const txt = await res.text().catch(() => "");
      setError(`Template aus Quest erstellen fehlgeschlagen (${res.status}) ${txt}`);
      return;
    }
    const created = (await res.json()) as { id: string };
    window.location.href = `/admin/quest-templates/${created.id}`;
  }

  const totalNeeded = useMemo(
    () => requirements.reduce((sum, req) => sum + req.qtyNeeded, 0),
    [requirements]
  );
  const totalDeliveredForProgress = useMemo(
    () => requirements.reduce((sum, req) => sum + Math.min(req.deliveredQty, req.qtyNeeded), 0),
    [requirements]
  );
  const totalCollectedPendingForProgress = useMemo(
    () =>
      requirements.reduce((sum, req) => {
        const delivered = Math.min(req.deliveredQty, req.qtyNeeded);
        const collectedPending = Math.max(Math.min(req.collectedQty, req.qtyNeeded) - delivered, 0);
        return sum + collectedPending;
      }, 0),
    [requirements]
  );
  const sortedRequirements = useMemo(() => {
    return requirements
      .map((req, index) => ({ req, index }))
      .sort((a, b) => {
        const aDone = Math.min(a.req.deliveredQty, a.req.qtyNeeded) >= a.req.qtyNeeded;
        const bDone = Math.min(b.req.deliveredQty, b.req.qtyNeeded) >= b.req.qtyNeeded;
        if (aDone === bDone) return a.index - b.index;
        return aDone ? 1 : -1;
      })
      .map((entry) => entry.req);
  }, [requirements]);
  const canAdmin = currentUserRole === "admin" || currentUserRole === "superAdmin";
  const isGuest = currentUserRole === "guest";
  const canEditQuest = useMemo(() => {
    if (!quest) return false;
    if (quest.isApproved) return canAdmin;
    return canAdmin || quest.createdByUserId === currentUserId;
  }, [quest, canAdmin, currentUserId]);
  const isQuestClosed = quest?.status === "DONE" || quest?.status === "ARCHIVED";
  const canEditQuestDetails = useMemo(() => {
    if (!quest) return false;
    if (canAdmin) return true;
    return quest.createdByUserId === currentUserId && !quest.isApproved && quest.status === "OPEN";
  }, [quest, canAdmin, currentUserId]);
  const detailsEditMode = editMode;
  const deliveredParticipants = useMemo(() => {
    const byUser = new Map<string, { username: string; totalQty: number }>();
    for (const reqContribs of Object.values(contributions)) {
      for (const c of reqContribs) {
        if (c.status !== "DELIVERED") continue;
        const key = c.userId;
        const existing = byUser.get(key);
        if (existing) {
          existing.totalQty += c.qty;
        } else {
          byUser.set(key, { username: c.username, totalQty: c.qty });
        }
      }
    }
    return [...byUser.values()].sort((a, b) => {
      if (b.totalQty !== a.totalQty) return b.totalQty - a.totalQty;
      return a.username.localeCompare(b.username, "de-DE");
    });
  }, [contributions]);

  return (
    <main className="qb-main">
      <h1>Quest-Details</h1>

      {quest ? (
        <Card className={quest.isPrioritized ? "qb-card-priority" : ""}>
          <div className="qb-inline" style={{ justifyContent: "space-between" }}>
            <strong>{quest.title}</strong>
            <div className="qb-inline">
              {quest.isPrioritized ? <Badge label="PRIORITAET" /> : null}
              {!quest.isApproved ? <Badge label="PENDING" /> : <Badge label="APPROVED" />}
              <Badge label={quest.status} />
            </div>
          </div>
          <div style={{ marginTop: 8 }}>
            <ProgressWithLegend
              delivered={totalDeliveredForProgress}
              collectedPending={totalCollectedPendingForProgress}
              remaining={Math.max(totalNeeded - totalDeliveredForProgress - totalCollectedPendingForProgress, 0)}
              max={totalNeeded}
            />
          </div>
          <p className="qb-muted">Erstellt von: {quest.createdByUsername ?? quest.createdByUserId ?? "Unbekannt"}</p>
          {!quest.isApproved ? (
            <p className="qb-muted">Diese Quest wartet auf Freigabe durch einen Admin.</p>
          ) : null}
          {!quest.isApproved && canAdmin ? (
            <div className="qb-inline">
              <Button type="button" variant="primary" onClick={approveQuest}>Quest freigeben</Button>
            </div>
          ) : null}
          {!detailsEditMode ? <p className="qb-muted">{quest.description}</p> : null}
          {!detailsEditMode ? (
            <p className="qb-muted">Abzugeben bei: {quest.handoverInfo?.trim() ? quest.handoverInfo : "Nicht gesetzt"}</p>
          ) : null}
          {canEditQuestDetails && detailsEditMode ? (
            <form onSubmit={updateQuestDetails} className="qb-form" style={{ marginTop: 8 }}>
              <TextInput
                placeholder="Titel"
                value={editTitle}
                onChange={(e) => setEditTitle(e.target.value)}
                required
              />
              <TextInput
                placeholder="Abzugeben bei (Wo und bei wem)"
                value={editHandoverInfo}
                onChange={(e) => setEditHandoverInfo(e.target.value)}
              />
              {canAdmin ? (
                <label className="qb-inline" style={{ alignItems: "center" }}>
                  <input
                    type="checkbox"
                    checked={editIsPrioritized}
                    onChange={(e) => setEditIsPrioritized(e.target.checked)}
                  />
                  <span>Quest priorisieren</span>
                </label>
              ) : null}
              <TextArea
                placeholder="Beschreibung"
                value={editDescription}
                onChange={(e) => setEditDescription(e.target.value)}
                rows={4}
                required
              />
              <Button type="submit" variant="primary" disabled={savingQuestDetails}>
                {savingQuestDetails ? "Speichert..." : "Quest-Details speichern"}
              </Button>
            </form>
          ) : null}
          {requirements.length > 0 ? (
            <div className="qb-grid">
              {sortedRequirements.map((req) => {
                const deliveredForProgress = Math.min(req.deliveredQty, req.qtyNeeded);
                const collectedForProgress = Math.min(req.collectedQty, req.qtyNeeded);
                const collectedPending = Math.max(collectedForProgress - deliveredForProgress, 0);
                const remaining = Math.max(req.qtyNeeded - collectedForProgress, 0);

                return (
                  <div key={req.id}>
                    <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                      <span>{req.itemName}</span>
                      <span className="qb-muted">{deliveredForProgress}/{req.qtyNeeded} {req.unit} abgegeben</span>
                    </div>
                    <ProgressWithLegend
                      delivered={deliveredForProgress}
                      collectedPending={collectedPending}
                      remaining={remaining}
                      max={req.qtyNeeded}
                    />
                  </div>
                );
              })}
            </div>
          ) : null}
          {canEditQuest ? (
            <div className="qb-inline" style={{ marginTop: 12, marginBottom: 8, gap: 12 }}>
              <Button type="button" variant={editMode ? "primary" : "secondary"} onClick={() => setEditMode((v) => !v)}>
                {editMode ? "Bearbeitungsmodus beenden" : "Bearbeitungsmodus"}
              </Button>
              {canAdmin ? (
                <Button type="button" variant="secondary" onClick={createTemplateFromQuest}>
                  Als Template speichern
                </Button>
              ) : null}
            </div>
          ) : null}
          {canEditQuest ? (
            <div className="qb-inline" style={{ gap: 12 }}>
              {questStatuses.map((s) => (
                <Button key={s} type="button" onClick={() => updateQuestStatus(s)} disabled={quest.status === s}>
                  {statusLabel(s)}
                </Button>
              ))}
            </div>
          ) : (
            <p className="qb-muted">Quest-Bearbeitung ist hier nicht erlaubt.</p>
          )}
        </Card>
      ) : null}

      {canEditQuest && editMode ? (
        <Card>
          <h2 className="qb-card-title">Requirement erstellen</h2>
          <form onSubmit={createRequirement} className="qb-form">
            <TextInput placeholder="Material / Item" value={newReqItem} onChange={(e) => setNewReqItem(e.target.value)} required />
            <TextInput type="number" min={1} value={newReqQty} onChange={(e) => setNewReqQty(Number(e.target.value))} required />
            <TextInput placeholder="Einheit" value={newReqUnit} onChange={(e) => setNewReqUnit(e.target.value)} required />
            <Button type="submit" variant="primary">Requirement speichern</Button>
          </form>
        </Card>
      ) : null}

      {error ? <p className="qb-error">{error}</p> : null}

      {isQuestClosed ? (
        <section className="qb-grid">
          <Card>
            <h2 className="qb-card-title">Danke an</h2>
            {deliveredParticipants.length === 0 ? (
              <p className="qb-muted">Keine abgegebenen Beitraege vorhanden.</p>
            ) : (
              <div className="qb-grid" style={{ gap: 6 }}>
                {deliveredParticipants.map((participant) => (
                  <div key={participant.username} className="qb-inline" style={{ justifyContent: "space-between" }}>
                    <strong>{participant.username}</strong>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </section>
      ) : (
      <section className="qb-grid">
        {sortedRequirements.map((req) => {
          const reqContributions = contributions[req.id] ?? [];
          const openContributions = reqContributions.filter(
            (c) => c.status === "CLAIMED" || c.status === "COLLECTED"
          );
          const deliveredForProgress = Math.min(req.deliveredQty, req.qtyNeeded);
          const collectedForProgress = Math.min(req.collectedQty, req.qtyNeeded);
          const collectedPending = Math.max(collectedForProgress - deliveredForProgress, 0);
          const remaining = Math.max(req.qtyNeeded - collectedForProgress, 0);
          const defaultVisibleContributions = openContributions.slice(-3);
          const isExpanded = expandedContributions[req.id] ?? false;
          const visibleContributions = isExpanded ? reqContributions : defaultVisibleContributions;
          const canToggleContributions = reqContributions.length > defaultVisibleContributions.length;

          return (
          <Card key={req.id}>
            <div className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong>{req.itemName}</strong>
              <span>{deliveredForProgress}/{req.qtyNeeded} {req.unit} abgegeben</span>
            </div>
            <ProgressWithLegend
              delivered={deliveredForProgress}
              collectedPending={collectedPending}
              remaining={remaining}
              max={req.qtyNeeded}
            />
            <p className="qb-muted">
              {deliveredForProgress}/{req.qtyNeeded} {req.unit} abgegeben | {collectedPending} gesammelt | {remaining} offen
            </p>
            {req.excessQty > 0 ? <p className="qb-muted">Zu viel geliefert: {req.excessQty} {req.unit}</p> : null}

            {isGuest ? (
              <p className="qb-muted">Gast-Accounts koennen keine Beitraege erstellen oder bearbeiten.</p>
            ) : (
              <form onSubmit={(e) => createContribution(req.id, e)} className="qb-form">
                <TextInput
                  type="number"
                  min={1}
                  value={newContribQty[req.id] ?? 1}
                  onChange={(e) => setNewContribQty((p) => ({ ...p, [req.id]: Number(e.target.value) }))}
                />
                <SelectInput
                  value={newContribStatus[req.id] ?? "CLAIMED"}
                  onChange={(e) => setNewContribStatus((p) => ({ ...p, [req.id]: e.target.value as ContributionStatus }))}
                >
                  {contributionStatuses.map((s) => <option key={s} value={s}>{statusLabel(s)}</option>)}
                </SelectInput>
                <TextInput
                  placeholder="Note optional"
                  value={newContribNote[req.id] ?? ""}
                  onChange={(e) => setNewContribNote((p) => ({ ...p, [req.id]: e.target.value }))}
                />
                <Button type="submit" variant="primary">Beitrag eintragen</Button>
              </form>
            )}

            <div className="qb-grid">
              {visibleContributions.map((c) => (
                <Card key={c.id}>
                  {(() => {
                    const isDelivered = c.status === "DELIVERED";
                    const isOwner = !isGuest && c.userId === currentUserId;
                    const isQuestCreator = quest?.createdByUserId != null && quest.createdByUserId === currentUserId;
                    const canMarkDelivered = !isGuest && (canAdmin || isQuestCreator);
                    return (
                  <>
                  <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                    <strong>{c.username}</strong>
                    <Badge label={c.status} />
                  </div>
                  <div>{c.qty}</div>
                  {c.note ? <div className="qb-muted">{c.note}</div> : null}
                  {isDelivered ? (
                    <p className="qb-muted">Abgegebene Beitraege koennen nicht mehr bearbeitet werden.</p>
                  ) : null}
                  {isOwner && !isDelivered ? (
                    <div className="qb-inline">
                      <Button
                        type="button"
                        variant="secondary"
                        onClick={() => {
                          setEditingContribution((prev) => ({ ...prev, [c.id]: !prev[c.id] }));
                          setEditContribQty((prev) => ({ ...prev, [c.id]: c.qty }));
                          setEditContribNote((prev) => ({ ...prev, [c.id]: c.note ?? "" }));
                        }}
                      >
                        {editingContribution[c.id] ? "Bearbeiten abbrechen" : "Beitrag bearbeiten"}
                      </Button>
                    </div>
                  ) : null}
                  {editingContribution[c.id] ? (
                    <form
                      className="qb-form"
                      onSubmit={(e) => {
                        e.preventDefault();
                        const qty = editContribQty[c.id] ?? c.qty;
                        const note = editContribNote[c.id] ?? "";
                        updateContribution(c.id, qty, note);
                      }}
                    >
                      <TextInput
                        type="number"
                        min={1}
                        value={editContribQty[c.id] ?? c.qty}
                        onChange={(e) => setEditContribQty((prev) => ({ ...prev, [c.id]: Number(e.target.value) }))}
                      />
                      <TextInput
                        placeholder="Notiz"
                        value={editContribNote[c.id] ?? (c.note ?? "")}
                        onChange={(e) => setEditContribNote((prev) => ({ ...prev, [c.id]: e.target.value }))}
                      />
                      <Button type="submit" variant="primary">Speichern</Button>
                    </form>
                  ) : null}
                  <div className="qb-inline">
                    {contributionStatuses.map((s) => {
                      const canSetStatus =
                        !isDelivered &&
                        (
                          (s === "DELIVERED" && canMarkDelivered) ||
                          (s !== "DELIVERED" && isOwner)
                        );
                      return (
                      <Button
                        key={s}
                        type="button"
                        disabled={c.status === s || !canSetStatus}
                        onClick={() => updateContributionStatus(c.id, s)}
                      >
                        {statusLabel(s)}
                      </Button>
                      );
                    })}
                  </div>
                  </>
                    );
                  })()}
                </Card>
              ))}
            </div>
            {!isExpanded && visibleContributions.length === 0 ? (
              <p className="qb-muted">Keine offenen Beiträge.</p>
            ) : null}
            {canToggleContributions ? (
              <div className="qb-inline">
                <Button
                  type="button"
                  variant="secondary"
                  onClick={() =>
                    setExpandedContributions((prev) => ({ ...prev, [req.id]: !isExpanded }))
                  }
                >
                  {isExpanded ? "Weniger anzeigen" : `Mehr anzeigen (${reqContributions.length})`}
                </Button>
              </div>
            ) : null}
          </Card>
          );
        })}
      </section>
      )}
    </main>
  );
}


