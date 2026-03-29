"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import Badge from "../../_components/ui/Badge";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextArea, TextInput } from "../../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";

type Breadcrumb = {
  id: string;
  name: string;
};

type Child = {
  id: string;
  name: string;
  itemCode?: string | null;
  badges: string[];
  openRequestCount: number;
  offerCount: number;
};

type Offer = {
  id: string;
  userId: string;
  username: string;
  note?: string | null;
  createdAt?: string | null;
};

type SearchRequest = {
  id: string;
  userId: string;
  username: string;
  averageQuality?: string | null;
  note?: string | null;
  status: "OPEN" | "FULFILLED" | "CANCELLED";
  createdAt?: string | null;
  offers: Offer[];
};

type Detail = {
  id: string;
  parentId?: string | null;
  name: string;
  description?: string | null;
  itemCode?: string | null;
  badges: string[];
  availableBadges: string[];
  breadcrumb: Breadcrumb[];
  children: Child[];
  requests: SearchRequest[];
};

export default function ItemSearchDetailPage({ params }: { params: { id: string } }) {
  const [detail, setDetail] = useState<Detail | null>(null);
  const [role, setRole] = useState<UserRole | null>(null);
  const [meUserId, setMeUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [averageQuality, setAverageQuality] = useState("");
  const [requestNote, setRequestNote] = useState("");
  const [offerNotes, setOfferNotes] = useState<Record<string, string>>({});

  const canEdit = role !== null && role !== "guest";
  const scmdbUrl = useMemo(() => (
    detail?.itemCode?.trim() ? `https://scmdb.net/?page=fab&fab=${encodeURIComponent(detail.itemCode.trim())}` : null
  ), [detail?.itemCode]);

  async function loadAll() {
    setError(null);
    const [meRes, detailRes] = await Promise.all([
      fetch("/api/me", { cache: "no-store" }),
      fetch(`/api/item-search/${params.id}`, { cache: "no-store" })
    ]);

    if (meRes.ok) {
      const me = await meRes.json();
      setRole((me.role as UserRole | undefined) ?? null);
      setMeUserId((me.userId as string | undefined) ?? null);
    }

    if (!detailRes.ok) {
      setError(`Item-Suche Detail load failed (${detailRes.status})`);
      return;
    }

    setDetail((await detailRes.json()) as Detail);
  }

  useEffect(() => {
    void loadAll();
  }, [params.id]);

  async function createRequest(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/${params.id}/requests`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          averageQuality: averageQuality || null,
          note: requestNote || null
        })
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche anlegen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      setAverageQuality("");
      setRequestNote("");
      setDetail((await res.json()) as Detail);
    } finally {
      setBusy(false);
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
      setDetail((await res.json()) as Detail);
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

      setDetail((await res.json()) as Detail);
    } finally {
      setBusy(false);
    }
  }

  async function deleteRequest(requestId: string) {
    if (!window.confirm("Suchanfrage wirklich loeschen?")) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch(`/api/item-search/requests/${requestId}`, {
        method: "DELETE"
      });

      if (!res.ok) {
        const text = await res.text().catch(() => "");
        setError(`Suche loeschen fehlgeschlagen (${res.status}) ${text}`);
        return;
      }

      setDetail((await res.json()) as Detail);
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="qb-main">
      <h1>Item-Suche</h1>

      {detail ? (
        <div className="qb-inline" style={{ marginBottom: 12, flexWrap: "wrap" }}>
          {detail.breadcrumb.map((item, index) => (
            <span key={item.id} className="qb-muted">
              {index > 0 ? " > " : ""}
              <a href={`/item-search/${item.id}`}>{item.name}</a>
            </span>
          ))}
        </div>
      ) : null}

      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <div className="qb-inline" style={{ justifyContent: "space-between" }}>
          <h2 className="qb-card-title">{detail?.name ?? "Item"}</h2>
          <div className="qb-inline" style={{ flexWrap: "wrap" }}>
            {detail?.badges.map((badge) => <Badge key={badge} label={badge} />)}
          </div>
        </div>
        {detail?.description ? <p className="qb-muted">{detail.description}</p> : <p className="qb-muted">Keine Beschreibung.</p>}
        {scmdbUrl ? (
          <div className="qb-inline" style={{ marginTop: 8 }}>
            <a href={scmdbUrl} target="_blank" rel="noreferrer" className="qb-nav-link">SCMDB oeffnen</a>
          </div>
        ) : null}
      </Card>

      {canEdit ? (
        <Card>
          <h2 className="qb-card-title">Suche anlegen</h2>
          <form className="qb-form" onSubmit={createRequest}>
            <TextInput
              placeholder="Average Quality / Durchschnittsqualitaet (optional)"
              value={averageQuality}
              onChange={(e) => setAverageQuality(e.target.value)}
            />
            <TextArea
              rows={3}
              placeholder="Notiz (optional)"
              value={requestNote}
              onChange={(e) => setRequestNote(e.target.value)}
            />
            <Button type="submit" variant="primary" disabled={busy}>
              {busy ? "Speichert..." : "Suche speichern"}
            </Button>
          </form>
        </Card>
      ) : null}

      <Card>
        <h2 className="qb-card-title">Offene Suchen</h2>
        {!detail || detail.requests.length === 0 ? (
          <p className="qb-muted">Aktuell sucht noch niemand dieses Item.</p>
        ) : (
          <div className="qb-grid">
            {detail.requests.map((request) => {
              const alreadyOffered = request.offers.some((offer) => offer.userId === meUserId);
              const canOffer = canEdit && request.userId !== meUserId && request.status === "OPEN" && !alreadyOffered;
              const canManageRequest = role === "admin" || role === "superAdmin" || request.userId === meUserId;

              return (
                <Card key={request.id}>
                  <div className="qb-inline" style={{ justifyContent: "space-between", gap: 12 }}>
                    <strong>{request.username}</strong>
                    <Badge label={request.status === "OPEN" ? "Offen" : request.status === "FULFILLED" ? "Erfuellt" : "Abgebrochen"} />
                  </div>
                  {request.averageQuality ? <div className="qb-muted">Durchschnittsqualitaet: {request.averageQuality}</div> : null}
                  {request.note ? <div className="qb-muted">{request.note}</div> : null}

                  <div className="qb-grid" style={{ gap: 8, marginTop: 8 }}>
                    <strong>Angebote</strong>
                    {request.offers.length === 0 ? (
                      <p className="qb-muted">Noch niemand hat Hilfe angeboten.</p>
                    ) : (
                      request.offers.map((offer) => (
                        <div key={offer.id}>
                          <div className="qb-inline" style={{ justifyContent: "space-between" }}>
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
                    <div className="qb-inline" style={{ marginTop: 8, flexWrap: "wrap" }}>
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
                      <Button
                        type="button"
                        variant="danger"
                        disabled={busy}
                        onClick={() => void deleteRequest(request.id)}
                      >
                        Suche loeschen
                      </Button>
                    </div>
                  ) : null}
                </Card>
              );
            })}
          </div>
        )}
      </Card>

      <Card>
        <h2 className="qb-card-title">Unterpunkte</h2>
        {!detail || detail.children.length === 0 ? (
          <p className="qb-muted">Noch keine Unterpunkte vorhanden.</p>
        ) : (
          <div className="qb-grid">
            {detail.children.map((child) => (
              <Card key={child.id}>
                <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                  <strong><a href={`/item-search/${child.id}`}>{child.name}</a></strong>
                  <div className="qb-inline" style={{ flexWrap: "wrap" }}>
                    {child.badges.map((badge) => <Badge key={badge} label={badge} />)}
                  </div>
                </div>
                <div className="qb-muted">{child.openRequestCount} Suchen offen · {child.offerCount} Angebote</div>
              </Card>
            ))}
          </div>
        )}
      </Card>
    </main>
  );
}
