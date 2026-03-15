"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../_components/ui/Badge";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { TextArea, TextInput } from "../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type Crafter = {
  userId: string;
  username: string;
};

type BlueprintTreeNode = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  isCraftable: boolean;
  crafters: Crafter[];
  children: BlueprintTreeNode[];
};

type BlueprintListResponse = {
  blueprints: BlueprintTreeNode[];
  availableBadges: string[];
};

type BlueprintBranchProps = {
  node: BlueprintTreeNode;
  depth?: number;
  editMode: boolean;
  draggedNodeId: string | null;
  moveBusyId: string | null;
  onDragStart: (node: BlueprintTreeNode) => void;
  onDragEnd: () => void;
  onDropOnNode: (targetNode: BlueprintTreeNode) => void;
};

function parseBadges(input: string) {
  return input.split(",").map((item) => item.trim()).filter(Boolean);
}

function toggleValue(values: string[], value: string) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

function findNodeById(nodeId: string, nodes: BlueprintTreeNode[]): BlueprintTreeNode | null {
  for (const node of nodes) {
    if (node.id === nodeId) return node;
    const childMatch = findNodeById(nodeId, node.children);
    if (childMatch) return childMatch;
  }
  return null;
}

function filterTreeByBadges(nodes: BlueprintTreeNode[], activeBadgeFilters: string[]): BlueprintTreeNode[] {
  if (activeBadgeFilters.length === 0) return nodes;
  const activeSet = new Set(activeBadgeFilters.map((item) => item.toLowerCase()));

  return nodes.flatMap((node) => {
    const filteredChildren = filterTreeByBadges(node.children, activeBadgeFilters);
    const matchesSelf = node.badges.some((badge) => activeSet.has(badge.toLowerCase()));

    if (!matchesSelf && filteredChildren.length === 0) return [];
    return [{ ...node, children: filteredChildren }];
  });
}

function BlueprintBranch({
  node,
  depth = 0,
  editMode,
  draggedNodeId,
  moveBusyId,
  onDragStart,
  onDragEnd,
  onDropOnNode
}: BlueprintBranchProps) {
  const isDragged = draggedNodeId === node.id;
  const canDropHere = editMode && draggedNodeId !== null && draggedNodeId !== node.id && moveBusyId === null;

  return (
    <div style={{ marginLeft: depth * 18, marginTop: depth === 0 ? 0 : 10 }}>
      <div
        className="qb-inline"
        style={{
          justifyContent: "space-between",
          alignItems: "center",
          padding: editMode ? "8px 10px" : 0,
          border: editMode ? "1px dashed rgba(199, 205, 214, 0.25)" : "none",
          borderRadius: editMode ? 10 : 0,
          opacity: isDragged ? 0.5 : 1
        }}
        draggable={editMode}
        onDragStart={() => onDragStart(node)}
        onDragEnd={onDragEnd}
        onDragOver={(event) => {
          if (canDropHere) event.preventDefault();
        }}
        onDrop={(event) => {
          event.preventDefault();
          if (canDropHere) onDropOnNode(node);
        }}
      >
        <div>
          <a href={`/blueprints/${node.id}`}><strong>{node.name}</strong></a>
        </div>
        <div className="qb-inline">
          {node.badges.map((badge) => <Badge key={badge} label={badge} />)}
          {node.crafters.length > 0 ? <span className="qb-muted">{node.crafters.length} Crafter</span> : null}
        </div>
      </div>
      {node.description ? <div className="qb-muted">{node.description}</div> : null}
      {editMode ? <div className="qb-muted">Hier ablegen, um es unter {node.name} einzuordnen.</div> : null}
      {node.children.map((child) => (
        <BlueprintBranch
          key={child.id}
          node={child}
          depth={depth + 1}
          editMode={editMode}
          draggedNodeId={draggedNodeId}
          moveBusyId={moveBusyId}
          onDragStart={onDragStart}
          onDragEnd={onDragEnd}
          onDropOnNode={onDropOnNode}
        />
      ))}
    </div>
  );
}

export default function BlueprintsPage() {
  const [data, setData] = useState<BlueprintListResponse | null>(null);
  const [role, setRole] = useState<UserRole | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [editMode, setEditMode] = useState(false);
  const [draggedNode, setDraggedNode] = useState<BlueprintTreeNode | null>(null);
  const [moveBusyId, setMoveBusyId] = useState<string | null>(null);
  const [activeBadgeFilters, setActiveBadgeFilters] = useState<string[]>([]);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [itemCode, setItemCode] = useState("");
  const [selectedBadges, setSelectedBadges] = useState<string[]>([]);
  const [newBadgesInput, setNewBadgesInput] = useState("");
  const [renamingBadge, setRenamingBadge] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState("");
  const [badgeBusy, setBadgeBusy] = useState<string | null>(null);

  const canEdit = role !== null && role !== "guest";
  const canStructureEdit = role === "admin" || role === "superAdmin";
  const canCreateBadges = role === "admin" || role === "superAdmin";
  const canCreateRoot = role === "admin" || role === "superAdmin";

  async function loadAll() {
    setError(null);
    const [meRes, bpRes] = await Promise.all([
      fetch("/api/me", { cache: "no-store" }),
      fetch("/api/blueprints", { cache: "no-store" })
    ]);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
    }

    if (!bpRes.ok) {
      setError(`Blueprints load failed (${bpRes.status})`);
      return;
    }

    setData((await bpRes.json()) as BlueprintListResponse);
  }

  useEffect(() => {
    void loadAll();
  }, []);

  async function createRoot(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const badges = [...selectedBadges, ...parseBadges(newBadgesInput)];
      const res = await fetch("/api/blueprints", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          description,
          itemCode: itemCode || null,
          badges
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Blueprint create failed (${res.status}) ${text}`);
        return;
      }

      const created = await res.json();
      setName("");
      setDescription("");
      setItemCode("");
      setSelectedBadges([]);
      setNewBadgesInput("");
      await loadAll();
      if (created?.id) {
        window.location.href = `/blueprints/${created.id}`;
      }
    } finally {
      setSubmitting(false);
    }
  }

  async function renameBadge(currentBadge: string) {
    const nextBadge = renameValue.trim();
    if (!nextBadge || nextBadge === currentBadge) {
      setRenamingBadge(null);
      setRenameValue("");
      return;
    }

    setError(null);
    setBadgeBusy(`rename:${currentBadge}`);
    try {
      const res = await fetch("/api/blueprints/badges/rename", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ from: currentBadge, to: nextBadge })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Badge umbenennen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      setActiveBadgeFilters((current) => current.map((item) => (item === currentBadge ? nextBadge : item)));
      setSelectedBadges((current) => current.map((item) => (item === currentBadge ? nextBadge : item)));
      setRenamingBadge(null);
      setRenameValue("");
      await loadAll();
    } finally {
      setBadgeBusy(null);
    }
  }

  async function deleteBadge(badge: string) {
    if (!window.confirm(`Badge "${badge}" wirklich loeschen? Er wird aus allen Blueprint-Eintraegen entfernt.`)) {
      return;
    }

    setError(null);
    setBadgeBusy(`delete:${badge}`);
    try {
      const res = await fetch("/api/blueprints/badges/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ badge })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Badge loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      if (activeBadgeFilters.includes(badge)) {
        setActiveBadgeFilters((current) => current.filter((item) => item !== badge));
      }
      setSelectedBadges((current) => current.filter((item) => item !== badge));
      setRenamingBadge(null);
      setRenameValue("");
      await loadAll();
    } finally {
      setBadgeBusy(null);
    }
  }

  async function moveNode(nodeId: string, parentId: string | null) {
    if (!data) return;

    const sourceNode = findNodeById(nodeId, data.blueprints);
    if (!sourceNode) return;

    setError(null);
    setMoveBusyId(nodeId);
    try {
      const res = await fetch(`/api/blueprints/${nodeId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: sourceNode.name,
          description: sourceNode.description ?? "",
          itemCode: sourceNode.itemCode ?? null,
          badges: sourceNode.badges,
          parentId
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Blueprint verschieben fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      setDraggedNode(null);
      await loadAll();
    } finally {
      setMoveBusyId(null);
    }
  }

  const filteredBlueprints = useMemo(() => filterTreeByBadges(data?.blueprints ?? [], activeBadgeFilters), [data, activeBadgeFilters]);
  const hasExplicitFilters = activeBadgeFilters.length > 0;

  return (
    <main className="qb-main">
      <h1>Blueprints</h1>

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">Filter</h2>
          {hasExplicitFilters ? (
            <button type="button" className="qb-nav-link" onClick={() => setActiveBadgeFilters([])} style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}>
              Filter zuruecksetzen
            </button>
          ) : null}
        </div>
        {!data || data.availableBadges.length === 0 ? (
          <p className="qb-muted">Noch keine Badges vorhanden.</p>
        ) : (
          <div className="qb-inline">
            {data.availableBadges.map((badge) => (
              <Button
                key={badge}
                type="button"
                variant={activeBadgeFilters.includes(badge) ? "primary" : "secondary"}
                onClick={() => setActiveBadgeFilters((current) => toggleValue(current, badge))}
              >
                {badge}
              </Button>
            ))}
          </div>
        )}
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <div
          className="qb-inline"
          style={{
            justifyContent: "space-between",
            padding: editMode ? "8px 10px" : 0,
            border: editMode ? "1px dashed rgba(199, 205, 214, 0.25)" : "none",
            borderRadius: editMode ? 10 : 0
          }}
          onDragOver={(event) => {
            if (editMode && draggedNode && moveBusyId === null) event.preventDefault();
          }}
          onDrop={(event) => {
            event.preventDefault();
            if (editMode && draggedNode && moveBusyId === null) {
              void moveNode(draggedNode.id, null);
            }
          }}
        >
          <h2 className="qb-card-title">Blueprints</h2>
          {editMode ? <span className="qb-muted">Hier ablegen als Oberpunkt</span> : null}
        </div>
        {filteredBlueprints.length === 0 ? (
          <p className="qb-muted">Keine Eintraege fuer den gewaehlten Filter.</p>
        ) : (
          filteredBlueprints.map((item) => (
            <BlueprintBranch
              key={item.id}
              node={item}
              editMode={editMode}
              draggedNodeId={draggedNode?.id ?? null}
              moveBusyId={moveBusyId}
              onDragStart={setDraggedNode}
              onDragEnd={() => setDraggedNode(null)}
              onDropOnNode={(targetNode) => {
                if (draggedNode) void moveNode(draggedNode.id, targetNode.id);
              }}
            />
          ))
        )}
      </Card>

      {(canStructureEdit || (canCreateBadges && data?.availableBadges.length)) ? (
        <Card>
          <h2 className="qb-card-title">Verwaltung</h2>
          {canStructureEdit ? (
            <div className="qb-form">
              <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                <strong>Struktur</strong>
                <Button
                  type="button"
                  variant={editMode ? "primary" : "secondary"}
                  onClick={() => {
                    setEditMode((value) => !value);
                    setDraggedNode(null);
                  }}
                >
                  {editMode ? "Bearbeiten beenden" : "Bearbeiten starten"}
                </Button>
              </div>
              <p className="qb-muted">
                {editMode
                  ? "Eintrag ziehen und auf einen anderen Eintrag oder auf die Wurzelebene ablegen."
                  : "Nur Admins duerfen die Struktur per Drag and Drop veraendern."}
              </p>
            </div>
          ) : null}

          {canCreateBadges && data?.availableBadges.length ? (
            <div className="qb-form">
              <strong>Badges</strong>
              {data.availableBadges.map((badge) => {
                const isRenaming = renamingBadge === badge;
                const renameBusy = badgeBusy === `rename:${badge}`;
                const deleteBusy = badgeBusy === `delete:${badge}`;

                return (
                  <div key={badge} className="qb-inline" style={{ justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
                    <Badge label={badge} />
                    {isRenaming ? (
                      <>
                        <TextInput value={renameValue} onChange={(e) => setRenameValue(e.target.value)} placeholder="Neuer Badge-Name" />
                        <div className="qb-inline" style={{ gap: 12 }}>
                          <Button type="button" variant="primary" disabled={renameBusy || deleteBusy} onClick={() => void renameBadge(badge)}>
                            {renameBusy ? "Speichert..." : "Speichern"}
                          </Button>
                          <Button
                            type="button"
                            variant="secondary"
                            disabled={renameBusy || deleteBusy}
                            onClick={() => {
                              setRenamingBadge(null);
                              setRenameValue("");
                            }}
                          >
                            Abbrechen
                          </Button>
                        </div>
                      </>
                    ) : (
                      <div className="qb-inline" style={{ gap: 12 }}>
                        <Button
                          type="button"
                          variant="secondary"
                          disabled={badgeBusy !== null}
                          onClick={() => {
                            setRenamingBadge(badge);
                            setRenameValue(badge);
                          }}
                        >
                          Umbenennen
                        </Button>
                        <Button type="button" variant="danger" disabled={badgeBusy !== null} onClick={() => void deleteBadge(badge)}>
                          {deleteBusy ? "Loescht..." : "Loeschen"}
                        </Button>
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          ) : null}
        </Card>
      ) : null}

      {canCreateRoot ? (
        <Card>
          <h2 className="qb-card-title">Neuen Oberpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createRoot}>
            <TextInput placeholder="Name" value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea placeholder="Beschreibung" rows={3} value={description} onChange={(e) => setDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name fuer SCMDB (optional)" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
            <div className="qb-inline" style={{ flexWrap: "wrap" }}>
              {data?.availableBadges.map((badge) => (
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
            <Button type="submit" variant="primary" disabled={submitting}>
              {submitting ? "Speichert..." : "Oberpunkt anlegen"}
            </Button>
          </form>
        </Card>
      ) : null}
    </main>
  );
}
