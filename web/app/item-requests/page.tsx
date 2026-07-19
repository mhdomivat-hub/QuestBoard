"use client";

import { useEffect, useMemo, useState } from "react";
import Badge from "../_components/ui/Badge";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";

type OpenItemRequest = {
  requestId: string;
  itemId: string;
  itemName: string;
  itemCode?: string | null;
  badges: string[];
  requesterUserId: string;
  requesterUsername: string;
  qty: number;
  averageQuality?: string | null;
  note?: string | null;
  hasResources: boolean;
  hasRecipe: boolean;
  crafterCount: number;
  totalQty: number;
  offerCount: number;
  createdAt?: string | null;
};

type OpenItemRequestResponse = {
  requests: OpenItemRequest[];
};

export default function ItemRequestsPage() {
  const [data, setData] = useState<OpenItemRequestResponse | null>(null);
  const [search, setSearch] = useState("");
  const [onlyHasResources, setOnlyHasResources] = useState(false);
  const [onlyHasRecipe, setOnlyHasRecipe] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch("/api/item-search/requests/open", { cache: "no-store" });
        if (!res.ok) {
          setError(`Anfragen konnten nicht geladen werden (${res.status})`);
          return;
        }
        setData((await res.json()) as OpenItemRequestResponse);
      } catch {
        setError("Anfragen konnten nicht geladen werden");
      } finally {
        setLoading(false);
      }
    }

    void load();
  }, []);

  const filteredRequests = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase();
    return (data?.requests ?? []).filter((request) => {
      if (onlyHasResources && !request.hasResources) return false;
      if (onlyHasRecipe && !request.hasRecipe) return false;
      if (!normalizedSearch) return true;

      const haystack = [
        request.itemName,
        request.itemCode ?? "",
        request.requesterUsername,
        request.note ?? "",
        ...request.badges
      ]
        .join(" ")
        .toLowerCase();

      return haystack.includes(normalizedSearch);
    });
  }, [data, onlyHasRecipe, onlyHasResources, search]);

  const totalRequests = data?.requests.length ?? 0;
  const withResourcesCount = data?.requests.filter((request) => request.hasResources).length ?? 0;
  const withRecipeCount = data?.requests.filter((request) => request.hasRecipe).length ?? 0;

  return (
    <main className="qb-main">
      <div className="qb-inline" style={{ justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
        <div>
          <h1>Offene Item-Anfragen</h1>
          <p className="qb-muted">Alle offenen Suchen mit Anfragesteller, Zeitpunkt und schneller Einschaetzung zu Ressourcen und Rezepten.</p>
        </div>
        <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
          <Badge label={`${filteredRequests.length} sichtbar`} />
          <Badge label={`${totalRequests} offen`} />
        </div>
      </div>

      <section className="qb-grid three" style={{ marginBottom: 16 }}>
        <Card>
          <h2 className="qb-card-title">Offen</h2>
          <strong style={{ fontSize: 24 }}>{totalRequests}</strong>
          <p className="qb-muted">Aktuell offene Item-Anfragen.</p>
        </Card>
        <Card>
          <h2 className="qb-card-title">Mit Ressourcen</h2>
          <strong style={{ fontSize: 24 }}>{withResourcesCount}</strong>
          <p className="qb-muted">Anfragen, bei denen Ressourcen bereits als vorhanden markiert sind.</p>
        </Card>
        <Card>
          <h2 className="qb-card-title">Mit Rezept</h2>
          <strong style={{ fontSize: 24 }}>{withRecipeCount}</strong>
          <p className="qb-muted">Anfragen fuer Items mit mindestens einem hinterlegten Crafter.</p>
        </Card>
      </section>

      <Card>
        <div className="qb-grid" style={{ gap: 12 }}>
          <div>
            <h2 className="qb-card-title">Filter</h2>
            <p className="qb-muted">Suche nach Item, Item-Code, Badge, Nutzer oder Notiz und schraenke auf Ressourcen oder Rezeptstatus ein.</p>
          </div>
          <input
            className="qb-input"
            placeholder="Suche nach Item, Nutzer, Badge oder Notiz"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
          />
          <div className="qb-inline" style={{ gap: 10, flexWrap: "wrap" }}>
            <label className="qb-inline" style={{ gap: 8 }}>
              <input type="checkbox" checked={onlyHasResources} onChange={(event) => setOnlyHasResources(event.target.checked)} />
              <span>Nur mit Ressourcen</span>
            </label>
            <label className="qb-inline" style={{ gap: 8 }}>
              <input type="checkbox" checked={onlyHasRecipe} onChange={(event) => setOnlyHasRecipe(event.target.checked)} />
              <span>Nur mit Rezept</span>
            </label>
            {(search || onlyHasResources || onlyHasRecipe) ? (
              <Button
                type="button"
                variant="secondary"
                onClick={() => {
                  setSearch("");
                  setOnlyHasResources(false);
                  setOnlyHasRecipe(false);
                }}
              >
                Filter zuruecksetzen
              </Button>
            ) : null}
          </div>
        </div>
      </Card>

      {loading ? <p className="qb-muted">Lade Anfragen...</p> : null}
      {error ? <p className="qb-error">{error}</p> : null}

      {!loading && !error ? (
        filteredRequests.length === 0 ? (
          <Card>
            <p className="qb-muted">Keine offenen Anfragen fuer die aktuellen Filter.</p>
          </Card>
        ) : (
          <div className="qb-grid" style={{ gap: 12 }}>
            {filteredRequests.map((request) => (
              <Card key={request.requestId}>
                <div className="qb-grid" style={{ gap: 10 }}>
                  <div className="qb-inline" style={{ justifyContent: "space-between", alignItems: "flex-start", gap: 12, flexWrap: "wrap" }}>
                    <div>
                      <strong><a href={`/items/${request.itemId}`}>{request.itemName}</a></strong>
                      {request.itemCode ? <div className="qb-muted">Code: {request.itemCode}</div> : null}
                      <div className="qb-muted" style={{ fontSize: 12 }}>
                        Angefragt von {request.requesterUsername}
                        {request.createdAt ? ` am ${new Date(request.createdAt).toLocaleString("de-DE")}` : ""}
                      </div>
                    </div>
                    <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap", justifyContent: "flex-end" }}>
                      <Badge label={`${request.qty}x`} />
                      <Badge label={request.hasResources ? "Ressourcen vorhanden" : "Keine Ressourcen"} />
                      <Badge label={request.hasRecipe ? `Rezept ${request.crafterCount}` : "Kein Rezept"} />
                    </div>
                  </div>

                  {request.badges.length > 0 ? (
                    <div className="qb-inline" style={{ gap: 8, flexWrap: "wrap" }}>
                      {request.badges.map((badge) => <Badge key={`${request.requestId}-${badge}`} label={badge} />)}
                    </div>
                  ) : null}

                  <div className="qb-inline" style={{ gap: 12, flexWrap: "wrap" }}>
                    <span className="qb-muted">Lagerbestand: {request.totalQty}</span>
                    <span className="qb-muted">Angebote: {request.offerCount}</span>
                    {request.averageQuality ? <span className="qb-muted">Qualitaet: {request.averageQuality}</span> : null}
                  </div>

                  {request.note ? <div className="qb-muted">{request.note}</div> : null}
                </div>
              </Card>
            ))}
          </div>
        )
      ) : null}
    </main>
  );
}
