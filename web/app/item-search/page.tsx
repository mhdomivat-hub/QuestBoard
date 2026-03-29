"use client";

import { useEffect, useMemo, useState } from "react";
import Badge from "../_components/ui/Badge";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";

type ItemSearchNode = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  openRequestCount: number;
  offerCount: number;
  children: ItemSearchNode[];
};

type ItemSearchListResponse = {
  items: ItemSearchNode[];
  availableBadges: string[];
};

function toggleValue(values: string[], value: string) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

function filterTree(nodes: ItemSearchNode[], activeBadges: string[]): ItemSearchNode[] {
  if (activeBadges.length === 0) return nodes;
  const badgeSet = new Set(activeBadges.map((item) => item.toLowerCase()));

  return nodes.flatMap((node) => {
    const filteredChildren = filterTree(node.children, activeBadges);
    const matchesSelf = node.badges.some((badge) => badgeSet.has(badge.toLowerCase()));
    if (!matchesSelf && filteredChildren.length === 0) return [];
    return [{ ...node, children: filteredChildren }];
  });
}

function SearchBranch({
  node,
  depth = 0,
  collapsedIds,
  onToggleCollapse
}: {
  node: ItemSearchNode;
  depth?: number;
  collapsedIds: string[];
  onToggleCollapse: (nodeId: string) => void;
}) {
  const hasChildren = node.children.length > 0;
  const isCollapsed = collapsedIds.includes(node.id);

  return (
    <div style={{ marginLeft: depth * 18, marginTop: depth === 0 ? 0 : 10 }}>
      <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, alignItems: "center" }}>
        <div>
          <div className="qb-inline" style={{ gap: 10 }}>
            {hasChildren ? (
              <button
                type="button"
                className="qb-nav-link"
                onClick={() => onToggleCollapse(node.id)}
                style={{ padding: "4px 8px", minWidth: 36 }}
              >
                {isCollapsed ? "+" : "-"}
              </button>
            ) : null}
            <a href={`/item-search/${node.id}`}><strong>{node.name}</strong></a>
          </div>
          {node.description ? <div className="qb-muted">{node.description}</div> : null}
        </div>
        <div className="qb-inline" style={{ flexWrap: "wrap", justifyContent: "flex-end" }}>
          {node.badges.map((badge) => <Badge key={badge} label={badge} />)}
          <span className="qb-muted">{node.openRequestCount} Suchen offen</span>
          <span className="qb-muted">{node.offerCount} Angebote</span>
        </div>
      </div>
      {!isCollapsed ? node.children.map((child) => (
        <SearchBranch key={child.id} node={child} depth={depth + 1} collapsedIds={collapsedIds} onToggleCollapse={onToggleCollapse} />
      )) : null}
    </div>
  );
}

export default function ItemSearchPage() {
  const [data, setData] = useState<ItemSearchListResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activeBadges, setActiveBadges] = useState<string[]>([]);
  const [collapsedIds, setCollapsedIds] = useState<string[]>([]);

  useEffect(() => {
    async function loadAll() {
      setError(null);
      const res = await fetch("/api/item-search", { cache: "no-store" });
      if (!res.ok) {
        setError(`Item-Suche load failed (${res.status})`);
        return;
      }
      setData((await res.json()) as ItemSearchListResponse);
    }

    void loadAll();
  }, []);

  const filteredItems = useMemo(() => filterTree(data?.items ?? [], activeBadges), [data, activeBadges]);

  return (
    <main className="qb-main">
      <h1>Item-Suche</h1>

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">Filter</h2>
          {activeBadges.length > 0 ? (
            <button
              type="button"
              className="qb-nav-link"
              onClick={() => setActiveBadges([])}
              style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}
            >
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
                variant={activeBadges.includes(badge) ? "primary" : "secondary"}
                onClick={() => setActiveBadges((current) => toggleValue(current, badge))}
              >
                {badge}
              </Button>
            ))}
          </div>
        )}
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <h2 className="qb-card-title">Gesuchte Items</h2>
        <p className="qb-muted">Die Suche baut auf denselben Item-Stammdaten wie Blueprints und Lager auf. Hier sieht man, wer gerade etwas sucht und wer Hilfe anbieten kann.</p>
        {filteredItems.length === 0 ? (
          <p className="qb-muted">Keine Eintraege fuer den gewaehlten Filter.</p>
        ) : (
          filteredItems.map((item) => (
            <SearchBranch
              key={item.id}
              node={item}
              collapsedIds={collapsedIds}
              onToggleCollapse={(nodeId) => setCollapsedIds((current) => toggleValue(current, nodeId))}
            />
          ))
        )}
      </Card>
    </main>
  );
}
