"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type Person = { userId: string; username: string };
type LocationFilter = { id: string; label: string };
type BadgeDefinition = { name: string; groupName?: string | null };
type RecipeResource = { id: string; resourceId: string; resourceName: string; slotName: string; quantity: number; minQuality?: number | null; totalStoredQty: number; people: Person[] };
type EntryResourceUsage = { id: string; resourceId: string; resourceName: string; quantity: number; quality?: number | null };
type Entry = { id: string; userId: string; username: string; locationId: string; locationLabel: string; qty: number; note?: string | null; createdAt?: string | null; resources: EntryResourceUsage[] };
type StorageChild = {
  id: string;
  name: string;
  itemCode?: string | null;
  badges: string[];
  hideFromBlueprints: boolean;
  crafterCount: number;
  totalQty: number;
  openSearchCount: number;
  entryCount: number;
  children: StorageChild[];
};
type Breadcrumb = { id: string; name: string };
type StorageDetail = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  availableBadges: string[];
  badgeDefinitions: BadgeDefinition[];
  hideFromBlueprints: boolean;
  crafterCount: number;
  totalQty: number;
  openSearchCount: number;
  entryCount: number;
  breadcrumb: Breadcrumb[];
  recipeResources: RecipeResource[];
  children: StorageChild[];
  entries: Entry[];
  availableUsers: Person[];
  locationFilters: LocationFilter[];
};
type Crafter = { userId: string; username: string };
type BlueprintDetail = { id: string; crafters: Crafter[] };
type SearchOffer = { id: string; userId: string; username: string; note?: string | null; hasResources: boolean };
type SearchRequest = {
  id: string;
  userId: string;
  username: string;
  qty: number;
  averageQuality?: string | null;
  note?: string | null;
  hasResources: boolean;
  status: "OPEN" | "FULFILLED" | "CANCELLED";
  offers: SearchOffer[];
};
type ItemSearchDetail = {
  id: string;
  requests: SearchRequest[];
};
type InventoryMatch = {
  requestId: string;
  itemId: string;
  matchedItemId: string;
  itemName: string;
  requesterUserId: string;
  requesterUsername: string;
  entryId: string;
  entryOwnerUserId: string;
  entryOwnerUsername: string;
  locationId: string;
  locationLabel: string;
  requestedQty: number;
  availableQty: number;
  averageQuality?: string | null;
  note?: string | null;
  hasEnoughQty: boolean;
  createdAt?: string | null;
};
type TreeNode = { id: string; name: string; children: TreeNode[] };
type ListResponse = { items: TreeNode[] };

function scmdbUrlForItemCode(itemCode?: string | null) {
  const value = itemCode?.trim();
  return value ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(value)}` : null;
}

function visibleBadges(badges: string[], itemCode?: string | null) {
  return badges.filter((badge) => badge !== "SCMDB" || Boolean(itemCode?.trim()));
}

function flattenItems(nodes: TreeNode[]): Array<{ id: string; name: string }> {
  const result: Array<{ id: string; name: string }> = [];
  const visit = (entries: TreeNode[], prefix = "") => {
    for (const entry of entries) {
      const label = prefix ? `${prefix} > ${entry.name}` : entry.name;
      result.push({ id: entry.id, name: label });
      visit(entry.children, label);
    }
  };
  visit(nodes);
  return result;
}

function parseBadges(input: string) {
  return input.split(",").map((item) => item.trim()).filter(Boolean);
}

function toggleValue(values: string[], value: string) {
  return values.includes(value) ? values.filter((item) => item !== value) : [...values, value];
}

function childSummaryParts(child: Pick<StorageChild, "crafterCount" | "totalQty" | "openSearchCount">) {
  const parts: string[] = [];
  if (child.crafterCount > 0) parts.push(`Crafter ${child.crafterCount}`);
  if (child.totalQty > 0) parts.push(`Lager ${child.totalQty}`);
  if (child.openSearchCount > 0) parts.push(`Suche ${child.openSearchCount}`);
  return parts;
}

function formatResourceQty(value: number) {
  return Number.isInteger(value) ? String(value) : value.toLocaleString("de-DE", { maximumFractionDigits: 3 });
}

function ChildBranch({
  child,
  depth = 0,
  collapsedIds,
  onToggleCollapse
}: {
  child: StorageChild;
  depth?: number;
  collapsedIds: string[];
  onToggleCollapse: (id: string) => void;
}) {
  const hasChildren = child.children.length > 0;
  const isCollapsed = collapsedIds.includes(child.id);

  return (
    <div style={{ marginLeft: depth * 18, marginTop: depth === 0 ? 0 : 10 }}>
      <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12 }}>
        <div>
          <div className="qb-inline" style={{ gap: 10 }}>
            {hasChildren ? (
              <button
                type="button"
                className="qb-nav-link"
                onClick={() => onToggleCollapse(child.id)}
                style={{ padding: "4px 8px", minWidth: 36 }}
              >
                {isCollapsed ? "+" : "-"}
              </button>
            ) : null}
            <strong><a href={`/items/${child.id}`}>{child.name}</a></strong>
          </div>
          {childSummaryParts(child).length > 0 ? <div className="qb-muted">{childSummaryParts(child).join(" | ")}</div> : null}
        </div>
        <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
          {child.hideFromBlueprints ? <Badge label="Ausgeblendet" /> : null}
          {visibleBadges(child.badges, child.itemCode).map((badge) => {
            const childScmdbUrl = scmdbUrlForItemCode(child.itemCode);
            return badge === "SCMDB" && childScmdbUrl ? (
              <a
                key={`${child.id}-scmdb`}
                href={childScmdbUrl}
                target="_blank"
                rel="noreferrer"
                className="qb-badge qb-badge-highlight"
              >
                SCMDB
              </a>
            ) : (
              <Badge key={`${child.id}-${badge}`} label={badge} />
            );
          })}
        </div>
      </div>
      {!isCollapsed ? child.children.map((nestedChild) => (
        <ChildBranch
          key={nestedChild.id}
          child={nestedChild}
          depth={depth + 1}
          collapsedIds={collapsedIds}
          onToggleCollapse={onToggleCollapse}
        />
      )) : null}
    </div>
  );
}

function groupBadgeDefinitions(definitions: BadgeDefinition[]) {
  const groups = new Map<string, BadgeDefinition[]>();
  for (const definition of definitions) {
    const group = definition.groupName?.trim() || "Ohne Gruppe";
    groups.set(group, [...(groups.get(group) ?? []), definition]);
  }
  return Array.from(groups.entries())
    .map(([groupName, badges]) => ({
      groupName,
      badges: badges.sort((left, right) => left.name.localeCompare(right.name, "de", { sensitivity: "base" }))
    }))
    .sort((left, right) => {
      if (left.groupName === "Ohne Gruppe") return 1;
      if (right.groupName === "Ohne Gruppe") return -1;
      return left.groupName.localeCompare(right.groupName, "de", { sensitivity: "base" });
    });
}

export default function ItemDetailPage({ params }: { params: { id: string } }) {
  const [storageDetail, setStorageDetail] = useState<StorageDetail | null>(null);
  const [blueprintDetail, setBlueprintDetail] = useState<BlueprintDetail | null>(null);
  const [searchDetail, setSearchDetail] = useState<ItemSearchDetail | null>(null);
  const [inventoryMatches, setInventoryMatches] = useState<InventoryMatch[]>([]);
  const [role, setRole] = useState<UserRole | null>(null);
  const [meUserId, setMeUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [itemCode, setItemCode] = useState("");
  const [selectedBadges, setSelectedBadges] = useState<string[]>([]);
  const [newBadgesInput, setNewBadgesInput] = useState("");
  const [hideFromBlueprints, setHideFromBlueprints] = useState(false);

  const [childName, setChildName] = useState("");
  const [childDescription, setChildDescription] = useState("");
  const [childItemCode, setChildItemCode] = useState("");
  const [childSelectedBadges, setChildSelectedBadges] = useState<string[]>([]);
  const [childNewBadgesInput, setChildNewBadgesInput] = useState("");

  const [locationId, setLocationId] = useState("");
  const [qty, setQty] = useState(1);
  const [note, setNote] = useState("");
  const [entryUserId, setEntryUserId] = useState("");
  const [entryResources, setEntryResources] = useState<Record<string, { quantity: string; quality: string }>>({});

  const [averageQuality, setAverageQuality] = useState("");
  const [requestQty, setRequestQty] = useState(1);
  const [requestNote, setRequestNote] = useState("");
  const [offerNotes, setOfferNotes] = useState<Record<string, string>>({});

  const [editingEntryId, setEditingEntryId] = useState<string | null>(null);
  const [editingEntryQty, setEditingEntryQty] = useState(1);
  const [editingEntryNote, setEditingEntryNote] = useState("");
  const [editingEntryResources, setEditingEntryResources] = useState<Record<string, { quantity: string; quality: string }>>({});
  const [targetedRequestEntryId, setTargetedRequestEntryId] = useState<string | null>(null);

  const [allItems, setAllItems] = useState<Array<{ id: string; name: string }>>([]);
  const [mergeTargetId, setMergeTargetId] = useState("");
  const [mergeKeepValuesFrom, setMergeKeepValuesFrom] = useState<"CURRENT" | "OTHER">("CURRENT");
  const [mergeParentChoice, setMergeParentChoice] = useState<"CURRENT" | "OTHER" | "ROOT">("CURRENT");
  const [collapsedBadgeGroups, setCollapsedBadgeGroups] = useState<string[]>([]);
  const [collapsedChildIds, setCollapsedChildIds] = useState<string[]>([]);

  const canEdit = role !== null && role !== "guest";
  const canAdmin = role === "admin" || role === "superAdmin";
  const amCrafter = Boolean(blueprintDetail?.crafters.some((crafter) => crafter.userId === meUserId));
  const groupedBadgeDefinitions = useMemo(() => groupBadgeDefinitions(storageDetail?.badgeDefinitions ?? []), [storageDetail?.badgeDefinitions]);
  const scmdbUrl = useMemo(() => scmdbUrlForItemCode(storageDetail?.itemCode), [storageDetail?.itemCode]);
  const recipeResources = storageDetail?.recipeResources ?? [];

  function resourcePayload(values: Record<string, { quantity: string; quality: string }>) {
    return Object.entries(values)
      .map(([resourceId, value]) => ({
        resourceId,
        quantity: Number(value.quantity),
        quality: value.quality.trim() ? Number(value.quality) : null
      }))
      .filter((entry) => Number.isFinite(entry.quantity) && entry.quantity > 0);
  }

  function defaultResourceInputs(resources: RecipeResource[]) {
    return Object.fromEntries(resources.map((resource) => [
      resource.resourceId,
      { quantity: String(resource.quantity), quality: resource.minQuality ? String(resource.minQuality) : "" }
    ]));
  }

  function resourceInputsFromEntry(entry: Entry) {
    if (entry.resources.length > 0) {
      return Object.fromEntries(entry.resources.map((resource) => [
        resource.resourceId,
        { quantity: String(resource.quantity), quality: resource.quality ? String(resource.quality) : "" }
      ]));
    }
    return defaultResourceInputs(recipeResources);
  }

  async function loadAll() {
    setError(null);
    const requests: Promise<Response>[] = [
      fetch("/api/me", { cache: "no-store" }),
      fetch(`/api/storage/items/${params.id}`, { cache: "no-store" }),
      fetch(`/api/blueprints/${params.id}`, { cache: "no-store" }),
      fetch(`/api/item-search/${params.id}`, { cache: "no-store" }),
      fetch("/api/item-search/matches/mine", { cache: "no-store" })
    ];
    if (canAdmin) {
      requests.push(fetch("/api/storage/items", { cache: "no-store" }));
    }

    const [meRes, storageRes, blueprintRes, searchRes, matchRes, listRes] = await Promise.all(requests);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
      setMeUserId((me.userId as string | undefined) ?? null);
      setEntryUserId((me.userId as string | undefined) ?? "");
    }

    if (!storageRes.ok || !blueprintRes.ok || !searchRes.ok || !matchRes.ok) {
      setError(`Item load failed (${storageRes.status}/${blueprintRes.status}/${searchRes.status}/${matchRes.status})`);
      return;
    }

    const storageBody = (await storageRes.json()) as StorageDetail;
    const blueprintBody = (await blueprintRes.json()) as BlueprintDetail;
    const searchBody = (await searchRes.json()) as ItemSearchDetail;
    const matchBody = (await matchRes.json()) as InventoryMatch[];

    setStorageDetail(storageBody);
    setBlueprintDetail(blueprintBody);
    setSearchDetail(searchBody);
    setInventoryMatches(matchBody.filter((match) => match.matchedItemId === params.id));
    setName(storageBody.name);
    setDescription(storageBody.description ?? "");
    setItemCode(storageBody.itemCode ?? "");
    setSelectedBadges(storageBody.badges);
    setHideFromBlueprints(storageBody.hideFromBlueprints);
    setCollapsedChildIds(storageBody.children.map((child) => child.id));
    if (!locationId && storageBody.locationFilters[0]) setLocationId(storageBody.locationFilters[0].id);
    if (Object.keys(entryResources).length === 0 && storageBody.recipeResources.length > 0) {
      setEntryResources(defaultResourceInputs(storageBody.recipeResources));
    }

    if (listRes?.ok) {
      const listBody = (await listRes.json()) as ListResponse;
      setAllItems(flattenItems(listBody.items).filter((item) => item.id !== storageBody.id));
    } else {
      setAllItems([]);
    }
  }

  useEffect(() => {
    void loadAll();
  }, [params.id, canAdmin]);

  async function saveItem(e: FormEvent) {
    e.preventDefault();
    if (!storageDetail) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${params.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          description,
          itemCode: itemCode || null,
          badges: [...selectedBadges, ...parseBadges(newBadgesInput)],
          hideFromBlueprints,
          parentId: storageDetail.parentId ?? null
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item update failed (${res.status}) ${text}`);
        return;
      }
      await loadAll();
      setNewBadgesInput("");
    } finally {
      setBusy(false);
    }
  }

  async function createChild(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/storage/items", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          parentId: params.id,
          name: childName,
          description: childDescription,
          itemCode: childItemCode || null,
          badges: [...childSelectedBadges, ...parseBadges(childNewBadgesInput)]
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Unterpunkt create failed (${res.status}) ${text}`);
        return;
      }
      const created = await res.json();
      if (created?.id) {
        window.location.href = `/items/${created.id}`;
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function toggleCraftSelf() {
    if (!blueprintDetail || !meUserId) return;
    setBusy(true);
    setError(null);
    try {
      const res = amCrafter
        ? await fetch(`/api/blueprints/${blueprintDetail.id}/crafters/${meUserId}`, { method: "DELETE" })
        : await fetch(`/api/blueprints/${blueprintDetail.id}/crafters`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({})
          });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Crafter update failed (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createEntry(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${params.id}/entries`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          locationId,
          qty,
          note: note || null,
          userId: canAdmin ? (entryUserId || null) : null,
          resources: resourcePayload(entryResources)
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Lager-Eintrag create failed (${res.status}) ${text}`);
        return;
      }
      setQty(1);
      setNote("");
      setEntryResources(defaultResourceInputs(recipeResources));
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function saveEntry(entryId: string) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/entries/${entryId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          qty: editingEntryQty,
          note: editingEntryNote || null,
          resources: resourcePayload(editingEntryResources)
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Eintrag update fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
      setEditingEntryId(null);
      setEditingEntryQty(1);
      setEditingEntryNote("");
      setEditingEntryResources({});
    } finally {
      setBusy(false);
    }
  }

  async function deleteEntry(entryId: string) {
    if (!window.confirm("Eintrag wirklich loeschen?")) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/entries/${entryId}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Eintrag loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createRequest(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/${params.id}/requests`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          qty: requestQty,
          averageQuality: averageQuality || null,
          note: requestNote || null
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche anlegen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      setRequestQty(1);
      setAverageQuality("");
      setRequestNote("");
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function fulfillRequestFromMatch(match: InventoryMatch) {
    if (!window.confirm(`Anfrage von ${match.requesterUsername} ueber ${match.requestedQty}x ${match.itemName} erfuellen?`)) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${match.requestId}/fulfill-from-entry`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ entryId: match.entryId })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Anfrage erfuellen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function createTargetedRequest(entry: Entry) {
    if (!storageDetail) return;
    setBusy(true);
    setTargetedRequestEntryId(entry.id);
    setError(null);
    try {
      const targetedNoteParts = [
        `Gezielte Anfrage fuer ${entry.username} bei ${entry.locationLabel}.`,
        entry.note ? `Eintragsnotiz: ${entry.note}` : null
      ].filter(Boolean);

      const res = await fetch(`/api/item-search/${params.id}/requests`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          averageQuality: null,
          note: targetedNoteParts.join(" ")
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Gezielte Anfrage fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      await loadAll();
    } finally {
      setBusy(false);
      setTargetedRequestEntryId(null);
    }
  }

  async function createOffer(requestId: string) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}/offers`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          note: offerNotes[requestId] || null
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Angebot speichern fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      setOfferNotes((current) => ({ ...current, [requestId]: "" }));
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function updateRequestResources(requestId: string, hasResources: boolean) {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}/resources`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ hasResources })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Ressourcenstatus speichern fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function updateRequestStatus(requestId: string, status: "FULFILLED" | "CANCELLED") {
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche aktualisieren fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function deleteRequest(requestId: string) {
    if (!window.confirm("Suchanfrage wirklich loeschen?")) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function mergeItems(e: FormEvent) {
    e.preventDefault();
    if (!mergeTargetId) {
      setError("Bitte zweiten Eintrag zum Zusammenfuehren auswaehlen.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/storage/items/${params.id}/merge`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          otherItemId: mergeTargetId,
          keepValuesFrom: mergeKeepValuesFrom,
          parentChoice: mergeParentChoice
        })
      });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Zusammenfuehren fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      const merged = await res.json();
      if (merged?.id) {
        window.location.href = `/items/${merged.id}`;
        return;
      }
      await loadAll();
    } finally {
      setBusy(false);
    }
  }

  async function deleteItem() {
    if (!storageDetail || !window.confirm(`Eintrag "${storageDetail.name}" wirklich komplett loeschen?`)) return;
    let reparentChildrenToParent = false;
    if (storageDetail.children.length > 0) {
      const childLabel = `${storageDetail.children.length} Unterpunkt${storageDetail.children.length === 1 ? "" : "e"}`;
      reparentChildrenToParent = storageDetail.parentId
        ? window.confirm(`Sollen ${childLabel} an den Oberpunkt von "${storageDetail.name}" gehaengt werden?`)
        : window.confirm(`Sollen ${childLabel} als neue Oberpunkte erhalten bleiben?`);
    }

    setBusy(true);
    setError(null);
    try {
      const query = reparentChildrenToParent ? "?reparentChildrenToParent=true" : "";
      const res = await fetch(`/api/storage/items/${storageDetail.id}${query}`, { method: "DELETE" });
      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Item loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }
      window.location.href = "/items";
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="qb-main">
      <h1>Item</h1>
      {storageDetail ? (
        <div className="qb-inline" style={{ marginBottom: 12, flexWrap: "wrap" }}>
          {storageDetail.breadcrumb.map((item, index) => (
            <span key={item.id} className="qb-muted">
              {index > 0 ? " > " : ""}
              <a href={`/items/${item.id}`}>{item.name}</a>
            </span>
          ))}
        </div>
      ) : null}

      {error ? <p className="qb-error">{error}</p> : null}

      {inventoryMatches.length > 0 ? (
        <Card>
          <h2 className="qb-card-title">Anfragen fuer mein Lager</h2>
          <div className="qb-grid" style={{ gap: 10 }}>
            {inventoryMatches.map((match) => (
              <div key={`${match.requestId}-${match.entryId}`} className="qb-grid" style={{ gap: 6 }}>
                <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12, alignItems: "flex-start" }}>
                  <div>
                    <strong>{match.requesterUsername} sucht {match.requestedQty}x</strong>
                    <div className="qb-muted">{match.itemName} bei {match.locationLabel}</div>
                    {match.averageQuality ? <div className="qb-muted">Durchschnittsqualitaet: {match.averageQuality}</div> : null}
                    {match.note ? <div className="qb-muted">{match.note}</div> : null}
                  </div>
                  <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
                    <Badge label={`Im Lager ${match.availableQty}`} />
                    {!match.hasEnoughQty ? <Badge label="Zu wenig Bestand" /> : null}
                    <Button
                      type="button"
                      variant="primary"
                      disabled={busy || !match.hasEnoughQty}
                      onClick={() => void fulfillRequestFromMatch(match)}
                    >
                      {busy ? "Speichert..." : "Anfrage erfuellen"}
                    </Button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </Card>
      ) : null}

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">{storageDetail?.name ?? "Item"}</h2>
          <div className="qb-inline" style={{ flexWrap: "wrap" }}>
            {storageDetail?.hideFromBlueprints ? <Badge label="In Blueprints ausgeblendet" /> : null}
            {visibleBadges(storageDetail?.badges ?? [], storageDetail?.itemCode).map((badge) => (
              badge === "SCMDB" && scmdbUrl ? (
                <a
                  key={`${storageDetail?.id ?? "item"}-scmdb`}
                  href={scmdbUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="qb-badge qb-badge-highlight"
                >
                  SCMDB
                </a>
              ) : (
                <Badge key={`${storageDetail?.id ?? "item"}-${badge}`} label={badge} />
              )
            ))}
          </div>
        </div>
        <p className="qb-muted">Zentrale Stammdaten fuer Crafting, Lager und Suche.</p>
        {storageDetail ? (
          <div className="qb-muted" style={{ marginTop: 8 }}>
            {[
              storageDetail.crafterCount > 0 ? `Crafter ${storageDetail.crafterCount}` : null,
              storageDetail.totalQty > 0 ? `Lager ${storageDetail.totalQty}` : null,
              storageDetail.openSearchCount > 0 ? `Suche ${storageDetail.openSearchCount}` : null
            ].filter(Boolean).join(" | ")}
          </div>
        ) : null}
        {scmdbUrl ? <div className="qb-inline" style={{ marginTop: 8 }}><a href={scmdbUrl} target="_blank" rel="noreferrer" className="qb-nav-link">SCMDB oeffnen</a></div> : null}
        {recipeResources.length > 0 ? (
          <div className="qb-grid" style={{ gap: 8, marginTop: 12 }}>
            <strong>Crafting-Ressourcen</strong>
            {recipeResources.map((resource) => (
              <div key={resource.id} className="qb-inline" style={{ justifyContent: "space-between", gap: 12, alignItems: "flex-start" }}>
                <div>
                  <a href={`/items/${resource.resourceId}`} className="qb-nav-link">{resource.resourceName}</a>
                  <div className="qb-muted">
                    {resource.slotName} · Menge {formatResourceQty(resource.quantity)}
                    {resource.minQuality ? ` · Min. Qualitaet ${resource.minQuality}` : ""}
                  </div>
                  {resource.people.length > 0 ? (
                    <div className="qb-muted">Im Lager bei {resource.people.map((person) => person.username).join(", ")}</div>
                  ) : null}
                </div>
                <Badge label={`Lager ${resource.totalStoredQty}`} />
              </div>
            ))}
          </div>
        ) : null}
        {canEdit && storageDetail ? (
          <form className="qb-form" onSubmit={saveItem}>
            <TextInput value={name} onChange={(e) => setName(e.target.value)} required />
            <TextArea rows={4} value={description} onChange={(e) => setDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
            <div className="qb-grid" style={{ gap: 10 }}>
              {groupedBadgeDefinitions.map((group) => (
                <div key={group.groupName} className="qb-grid" style={{ gap: 6 }}>
                  <button
                    type="button"
                    className="qb-nav-link"
                    onClick={() => setCollapsedBadgeGroups((current) => toggleValue(current, group.groupName))}
                    style={{ textAlign: "left", padding: 0, background: "none", border: "none", cursor: "pointer" }}
                  >
                    <strong>{collapsedBadgeGroups.includes(group.groupName) ? "+ " : "- "}{group.groupName}</strong>
                  </button>
                  {!collapsedBadgeGroups.includes(group.groupName) ? (
                    <div className="qb-inline">
                      {group.badges.map((badge) => (
                        <Button key={badge.name} type="button" variant={selectedBadges.includes(badge.name) ? "primary" : "secondary"} onClick={() => setSelectedBadges((current) => toggleValue(current, badge.name))}>{badge.name}</Button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
            {canAdmin ? <TextInput placeholder="Neue Badges (kommagetrennt)" value={newBadgesInput} onChange={(e) => setNewBadgesInput(e.target.value)} /> : null}
            {canAdmin ? (
              <label className="qb-inline" style={{ gap: 8, alignItems: "center" }}>
                <input type="checkbox" checked={hideFromBlueprints} onChange={(e) => setHideFromBlueprints(e.target.checked)} />
                <span>In Blueprints ausblenden</span>
              </label>
            ) : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Stammdaten speichern"}</Button>
          </form>
        ) : null}
      </Card>

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">Crafting</h2>
          {canEdit ? (
            <Button type="button" variant={amCrafter ? "secondary" : "primary"} onClick={toggleCraftSelf} disabled={busy}>
              {amCrafter ? "Ich kann das nicht mehr craften" : "Ich kann das craften"}
            </Button>
          ) : null}
        </div>
        {!blueprintDetail || blueprintDetail.crafters.length === 0 ? (
          <p className="qb-muted">Noch niemand in der Org kann dieses Item craften.</p>
        ) : (
          <div className="qb-inline" style={{ flexWrap: "wrap" }}>
            {blueprintDetail.crafters.map((crafter) => <Badge key={crafter.userId} label={crafter.username} />)}
          </div>
        )}
      </Card>

      <Card>
        <h2 className="qb-card-title">Lager</h2>
        <p className="qb-muted">Aktuell eingelagert: {storageDetail?.totalQty ?? 0}</p>
        {!storageDetail || storageDetail.entries.length === 0 ? <p className="qb-muted">Noch keine Eintraege vorhanden.</p> : (
          <div className="qb-grid">
            {storageDetail.entries.map((entry) => (
              <Card key={entry.id}>
                <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                  <strong>{entry.username}</strong>
                  <span>{entry.qty}</span>
                </div>
                <div className="qb-muted">{entry.locationLabel}</div>
                {editingEntryId === entry.id ? (
                  <div className="qb-form" style={{ marginTop: 8 }}>
                    <TextInput type="number" min={1} value={editingEntryQty} onChange={(e) => setEditingEntryQty(Number(e.target.value))} required />
                    <TextInput placeholder="Notiz (optional)" value={editingEntryNote} onChange={(e) => setEditingEntryNote(e.target.value)} />
                    {recipeResources.length > 0 ? (
                      <div className="qb-grid" style={{ gap: 8 }}>
                        <strong>Verwendete Ressourcen</strong>
                        {recipeResources.map((resource) => {
                          const value = editingEntryResources[resource.resourceId] ?? { quantity: "", quality: "" };
                          return (
                            <div key={`${entry.id}-${resource.resourceId}`} className="qb-grid" style={{ gap: 6 }}>
                              <a href={`/items/${resource.resourceId}`} className="qb-nav-link">{resource.resourceName}</a>
                              <div className="qb-inline" style={{ gap: 8 }}>
                                <TextInput
                                  type="number"
                                  min={0}
                                  step="0.001"
                                  placeholder={`Menge ${formatResourceQty(resource.quantity)}`}
                                  value={value.quantity}
                                  onChange={(e) => setEditingEntryResources((current) => ({ ...current, [resource.resourceId]: { ...value, quantity: e.target.value } }))}
                                />
                                <TextInput
                                  type="number"
                                  min={0}
                                  max={1000}
                                  placeholder="Qualitaet"
                                  value={value.quality}
                                  onChange={(e) => setEditingEntryResources((current) => ({ ...current, [resource.resourceId]: { ...value, quality: e.target.value } }))}
                                />
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    ) : null}
                    <div className="qb-inline">
                      <Button type="button" variant="primary" onClick={() => void saveEntry(entry.id)} disabled={busy}>
                        {busy ? "Speichert..." : "Aenderung speichern"}
                      </Button>
                      <Button
                        type="button"
                        variant="secondary"
                        onClick={() => {
                          setEditingEntryId(null);
                          setEditingEntryQty(1);
                          setEditingEntryNote("");
                          setEditingEntryResources({});
                        }}
                        disabled={busy}
                      >
                        Bearbeiten beenden
                      </Button>
                    </div>
                  </div>
                ) : (
                  <>
                    {entry.note ? <div className="qb-muted">{entry.note}</div> : null}
                    {entry.resources.length > 0 ? (
                      <div className="qb-grid" style={{ gap: 4, marginTop: 8 }}>
                        {entry.resources.map((resource) => (
                          <div key={resource.id} className="qb-muted">
                            <a href={`/items/${resource.resourceId}`} className="qb-nav-link">{resource.resourceName}</a>
                            {" "}· {formatResourceQty(resource.quantity)}
                            {resource.quality ? ` · Q${resource.quality}` : ""}
                          </div>
                        ))}
                      </div>
                    ) : null}
                  </>
                )}
                <div className="qb-inline">
                  {(canAdmin || entry.userId === meUserId) ? (
                    <>
                      <Button
                        type="button"
                        variant={editingEntryId === entry.id ? "primary" : "secondary"}
                        onClick={() => {
                          setEditingEntryId(entry.id);
                          setEditingEntryQty(entry.qty);
                          setEditingEntryNote(entry.note ?? "");
                          setEditingEntryResources(resourceInputsFromEntry(entry));
                        }}
                        disabled={busy}
                      >
                        Menge aendern
                      </Button>
                      <Button type="button" variant="danger" onClick={() => void deleteEntry(entry.id)} disabled={busy}>Eintrag loeschen</Button>
                    </>
                  ) : null}
                  {canEdit && entry.userId !== meUserId ? (
                    <Button
                      type="button"
                      variant="secondary"
                      onClick={() => void createTargetedRequest(entry)}
                      disabled={busy}
                    >
                      {targetedRequestEntryId === entry.id ? "Erstellt..." : "Anfrage erstellen"}
                    </Button>
                  ) : null}
                </div>
              </Card>
            ))}
          </div>
        )}

        {canEdit && storageDetail ? (
          <form className="qb-form" onSubmit={createEntry}>
            {canAdmin ? (
              <SelectInput value={entryUserId} onChange={(e) => setEntryUserId(e.target.value)}>
                {storageDetail.availableUsers.map((user) => <option key={user.userId} value={user.userId}>{user.username}</option>)}
              </SelectInput>
            ) : null}
            <SelectInput value={locationId} onChange={(e) => setLocationId(e.target.value)}>
              {storageDetail.locationFilters.map((location) => <option key={location.id} value={location.id}>{location.label}</option>)}
            </SelectInput>
            <TextInput type="number" min={1} value={qty} onChange={(e) => setQty(Number(e.target.value))} required />
            <TextInput placeholder="Notiz (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
            {recipeResources.length > 0 ? (
              <div className="qb-grid" style={{ gap: 8 }}>
                <strong>Verwendete Ressourcen</strong>
                {recipeResources.map((resource) => {
                  const value = entryResources[resource.resourceId] ?? { quantity: String(resource.quantity), quality: resource.minQuality ? String(resource.minQuality) : "" };
                  return (
                    <div key={`new-${resource.resourceId}`} className="qb-grid" style={{ gap: 6 }}>
                      <a href={`/items/${resource.resourceId}`} className="qb-nav-link">{resource.resourceName}</a>
                      <div className="qb-muted">{resource.slotName} · Vorgabe {formatResourceQty(resource.quantity)}</div>
                      <div className="qb-inline" style={{ gap: 8 }}>
                        <TextInput
                          type="number"
                          min={0}
                          step="0.001"
                          placeholder="Menge"
                          value={value.quantity}
                          onChange={(e) => setEntryResources((current) => ({ ...current, [resource.resourceId]: { ...value, quantity: e.target.value } }))}
                        />
                        <TextInput
                          type="number"
                          min={0}
                          max={1000}
                          placeholder="Qualitaet"
                          value={value.quality}
                          onChange={(e) => setEntryResources((current) => ({ ...current, [resource.resourceId]: { ...value, quality: e.target.value } }))}
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Lager-Eintrag speichern"}</Button>
          </form>
        ) : null}
      </Card>

      <Card>
        <h2 className="qb-card-title">Suche</h2>
        {!searchDetail || searchDetail.requests.length === 0 ? (
          <p className="qb-muted">Aktuell sucht noch niemand dieses Item.</p>
        ) : (
          <div className="qb-grid">
            {searchDetail.requests.map((request) => {
              const canOffer = canEdit && request.userId !== meUserId && request.status === "OPEN";
              const canManageRequest = canAdmin || request.userId === meUserId;

              return (
                <Card key={request.id}>
                  <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12 }}>
                    <strong>{request.username}</strong>
                    <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
                      {request.hasResources ? <Badge label="Ressourcen vorhanden" /> : null}
                      <Badge label={request.status === "OPEN" ? "Offen" : request.status === "FULFILLED" ? "Erfuellt" : "Abgebrochen"} />
                    </div>
                  </div>
                  <div className="qb-muted">Menge: {request.qty}</div>
                  {request.averageQuality ? <div className="qb-muted">Durchschnittsqualitaet: {request.averageQuality}</div> : null}
                  {request.note ? <div className="qb-muted">{request.note}</div> : null}
                  <div className="qb-grid" style={{ gap: 8, marginTop: 8 }}>
                    <strong>Angebote</strong>
                    {request.offers.length === 0 ? (
                      <p className="qb-muted">Noch niemand hat Hilfe angeboten.</p>
                    ) : (
                      request.offers.map((offer) => (
                        <div key={offer.id}>
                          <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12 }}>
                            <span>{offer.username}</span>
                          </div>
                          {offer.note ? <div className="qb-muted">{offer.note}</div> : null}
                        </div>
                      ))
                    )}
                  </div>
                  {canOffer ? (
                    <div className="qb-form" style={{ marginTop: 8 }}>
                      <TextArea
                        rows={2}
                        placeholder="Was kannst du bereitstellen? (optional)"
                        value={offerNotes[request.id] ?? ""}
                        onChange={(e) => setOfferNotes((current) => ({ ...current, [request.id]: e.target.value }))}
                      />
                      <Button type="button" variant="primary" disabled={busy} onClick={() => void createOffer(request.id)}>
                        {busy ? "Speichert..." : "Ich kann etwas bereitstellen"}
                      </Button>
                    </div>
                  ) : null}
                  {canManageRequest ? (
                    <div className="qb-inline" style={{ marginTop: 8 }}>
                      {request.status === "OPEN" && !request.hasResources ? (
                        <Button
                          type="button"
                          variant="secondary"
                          disabled={busy}
                          onClick={() => void updateRequestResources(request.id, true)}
                        >
                          Ich habe die Ressourcen dafuer
                        </Button>
                      ) : null}
                      {request.status === "OPEN" ? (
                        <>
                          <Button
                            type="button"
                            variant="primary"
                            disabled={busy}
                            onClick={() => void updateRequestStatus(request.id, "FULFILLED")}
                          >
                            Als erhalten schliessen
                          </Button>
                          <Button
                            type="button"
                            variant="secondary"
                            disabled={busy}
                            onClick={() => void updateRequestStatus(request.id, "CANCELLED")}
                          >
                            Abbrechen
                          </Button>
                        </>
                      ) : null}
                      <Button type="button" variant="danger" disabled={busy} onClick={() => void deleteRequest(request.id)}>
                        Suche loeschen
                      </Button>
                    </div>
                  ) : null}
                </Card>
              );
            })}
          </div>
        )}
        {canEdit ? (
          <form className="qb-form" onSubmit={createRequest}>
            <TextInput type="number" min={1} value={requestQty} onChange={(e) => setRequestQty(Number(e.target.value))} required />
            <TextInput placeholder="Average Quality / Durchschnittsqualitaet (optional)" value={averageQuality} onChange={(e) => setAverageQuality(e.target.value)} />
            <TextArea rows={3} placeholder="Notiz (optional)" value={requestNote} onChange={(e) => setRequestNote(e.target.value)} />
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Suche speichern"}</Button>
          </form>
        ) : null}
      </Card>

      <Card>
        <h2 className="qb-card-title">Unterpunkte</h2>
        {!storageDetail || storageDetail.children.length === 0 ? (
          <p className="qb-muted">Noch keine Unterpunkte vorhanden.</p>
        ) : (
          <div className="qb-grid">
            {storageDetail.children.map((child) => (
              <ChildBranch
                key={child.id}
                child={child}
                collapsedIds={collapsedChildIds}
                onToggleCollapse={(id) => setCollapsedChildIds((current) => toggleValue(current, id))}
              />
            ))}
          </div>
        )}
      </Card>

      {canEdit ? (
        <Card>
          <h2 className="qb-card-title">Unterpunkt anlegen</h2>
          <form className="qb-form" onSubmit={createChild}>
            <TextInput placeholder="Name" value={childName} onChange={(e) => setChildName(e.target.value)} required />
            <TextArea rows={3} placeholder="Beschreibung" value={childDescription} onChange={(e) => setChildDescription(e.target.value)} />
            <TextInput placeholder="Interner Item-Name (optional)" value={childItemCode} onChange={(e) => setChildItemCode(e.target.value)} />
            <div className="qb-grid" style={{ gap: 10 }}>
              {groupedBadgeDefinitions.map((group) => (
                <div key={group.groupName} className="qb-grid" style={{ gap: 6 }}>
                  <button
                    type="button"
                    className="qb-nav-link"
                    onClick={() => setCollapsedBadgeGroups((current) => toggleValue(current, group.groupName))}
                    style={{ textAlign: "left", padding: 0, background: "none", border: "none", cursor: "pointer" }}
                  >
                    <strong>{collapsedBadgeGroups.includes(group.groupName) ? "+ " : "- "}{group.groupName}</strong>
                  </button>
                  {!collapsedBadgeGroups.includes(group.groupName) ? (
                    <div className="qb-inline">
                      {group.badges.map((badge) => (
                        <Button key={badge.name} type="button" variant={childSelectedBadges.includes(badge.name) ? "primary" : "secondary"} onClick={() => setChildSelectedBadges((current) => toggleValue(current, badge.name))}>{badge.name}</Button>
                      ))}
                    </div>
                  ) : null}
                </div>
              ))}
            </div>
            {canAdmin ? <TextInput placeholder="Neue Badges (kommagetrennt)" value={childNewBadgesInput} onChange={(e) => setChildNewBadgesInput(e.target.value)} /> : null}
            <Button type="submit" variant="primary" disabled={busy}>{busy ? "Speichert..." : "Unterpunkt anlegen"}</Button>
          </form>
        </Card>
      ) : null}

      {canAdmin ? (
        <Card>
          <h2 className="qb-card-title">Admin</h2>
          <form className="qb-form" onSubmit={mergeItems}>
            <strong>Eintraege zusammenfuehren</strong>
            <SelectInput value={mergeTargetId} onChange={(e) => setMergeTargetId(e.target.value)} required>
              <option value="">Zweiten Eintrag auswaehlen</option>
              {allItems.map((item) => (
                <option key={item.id} value={item.id}>{item.name}</option>
              ))}
            </SelectInput>
            <SelectInput value={mergeKeepValuesFrom} onChange={(e) => setMergeKeepValuesFrom(e.target.value as "CURRENT" | "OTHER")}>
              <option value="CURRENT">Titel/Beschreibung/Item-Code von diesem Eintrag behalten</option>
              <option value="OTHER">Titel/Beschreibung/Item-Code vom anderen Eintrag behalten</option>
            </SelectInput>
            <SelectInput value={mergeParentChoice} onChange={(e) => setMergeParentChoice(e.target.value as "CURRENT" | "OTHER" | "ROOT")}>
              <option value="CURRENT">Oberpunkt von diesem Eintrag behalten</option>
              <option value="OTHER">Oberpunkt vom anderen Eintrag behalten</option>
              <option value="ROOT">Kein Oberpunkt</option>
            </SelectInput>
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Fuehrt zusammen..." : "Zusammenfuehren"}
            </Button>
          </form>
          <Button type="button" variant="danger" onClick={deleteItem} disabled={busy}>{busy ? "Loescht..." : "Item komplett loeschen"}</Button>
        </Card>
      ) : null}
    </main>
  );
}
