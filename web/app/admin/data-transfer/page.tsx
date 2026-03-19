"use client";

import { FormEvent, useState } from "react";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextInput } from "../../_components/ui/Input";

type TransferSectionKey =
  | "users"
  | "quests"
  | "requirements"
  | "contributions"
  | "blueprints"
  | "blueprintCrafters"
  | "storageLocations"
  | "storageEntries"
  | "invites"
  | "usernameChangeRequests"
  | "questTemplates"
  | "questTemplateRequirements"
  | "passwordResetRequests"
  | "passwordResetTokens"
  | "apiTokens"
  | "auditEvents";

const TRANSFER_SECTIONS: { key: TransferSectionKey; label: string }[] = [
  { key: "users", label: "User" },
  { key: "quests", label: "Quests" },
  { key: "requirements", label: "Requirements" },
  { key: "contributions", label: "Contributions" },
  { key: "blueprints", label: "Blueprints" },
  { key: "blueprintCrafters", label: "Blueprint Crafter" },
  { key: "storageLocations", label: "Storage Locations" },
  { key: "storageEntries", label: "Storage Entries" },
  { key: "invites", label: "Invites" },
  { key: "usernameChangeRequests", label: "Username Change Requests" },
  { key: "questTemplates", label: "Quest Templates" },
  { key: "questTemplateRequirements", label: "Template Requirements" },
  { key: "passwordResetRequests", label: "Password Reset Requests" },
  { key: "passwordResetTokens", label: "Password Reset Tokens" },
  { key: "apiTokens", label: "API Tokens" },
  { key: "auditEvents", label: "Audit Log" }
];

type TransferResult = {
  manifest: {
    version: number;
    generatedAt: string;
    counts: {
      users: number;
      quests: number;
      requirements: number;
      contributions: number;
      blueprints: number;
      blueprintCrafters: number;
      storageLocations: number;
      storageEntries: number;
      invites: number;
      usernameChangeRequests: number;
      questTemplates: number;
      questTemplateRequirements: number;
      passwordResetRequests: number;
      passwordResetTokens: number;
      apiTokens: number;
      auditEvents: number;
    };
  };
  chunksFetched: number;
  sections: string[];
  importResult: Record<string, number>;
};

type PushResult = {
  manifest: TransferResult["manifest"];
  chunksSent: number;
  sections: string[];
  importResult: Record<string, number>;
};

export default function AdminDataTransferPage() {
  const [sourceBaseURL, setSourceBaseURL] = useState("");
  const [sourceToken, setSourceToken] = useState("");
  const [targetBaseURL, setTargetBaseURL] = useState("");
  const [targetToken, setTargetToken] = useState("");
  const [selectedSections, setSelectedSections] = useState<TransferSectionKey[]>(TRANSFER_SECTIONS.map((item) => item.key));
  const [pullBusy, setPullBusy] = useState(false);
  const [pushBusy, setPushBusy] = useState(false);
  const [pullError, setPullError] = useState<string | null>(null);
  const [pushError, setPushError] = useState<string | null>(null);
  const [pullResult, setPullResult] = useState<TransferResult | null>(null);
  const [pushResult, setPushResult] = useState<PushResult | null>(null);
  const [copyState, setCopyState] = useState<string | null>(null);

  function toggleSection(section: TransferSectionKey) {
    setSelectedSections((current) =>
      current.includes(section) ? current.filter((item) => item !== section) : [...current, section]
    );
  }

  async function copyCurrentToken() {
    setCopyState(null);
    try {
      const res = await fetch("/api/admin/data/current-token", { cache: "no-store" });
      if (!res.ok) {
        setCopyState(`Token konnte nicht geladen werden (${res.status})`);
        return;
      }
      const body = (await res.json()) as { token?: string };
      if (!body.token) {
        setCopyState("Kein Token verfuegbar");
        return;
      }
      await navigator.clipboard.writeText(body.token);
      setCopyState("Token kopiert");
    } catch (err) {
      setCopyState(err instanceof Error ? err.message : "Token kopieren fehlgeschlagen");
    }
  }

  async function onPullSubmit(e: FormEvent) {
    e.preventDefault();
    if (selectedSections.length === 0) {
      setPullError("Bitte mindestens einen Bereich auswaehlen.");
      return;
    }
    setPullBusy(true);
    setPullError(null);
    setPullResult(null);

    try {
      const res = await fetch("/api/admin/data/transfer-remote", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sourceBaseURL, sourceToken, sections: selectedSections })
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setPullError(body || `Transfer failed (${res.status})`);
        return;
      }

      setPullResult((await res.json()) as TransferResult);
    } catch (err) {
      setPullError(err instanceof Error ? err.message : "Transfer failed");
    } finally {
      setPullBusy(false);
    }
  }

  async function onPushSubmit(e: FormEvent) {
    e.preventDefault();
    if (selectedSections.length === 0) {
      setPushError("Bitte mindestens einen Bereich auswaehlen.");
      return;
    }
    setPushBusy(true);
    setPushError(null);
    setPushResult(null);

    try {
      const res = await fetch("/api/admin/data/push-remote", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetBaseURL, targetToken, sections: selectedSections })
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setPushError(body || `Upload failed (${res.status})`);
        return;
      }

      setPushResult((await res.json()) as PushResult);
    } catch (err) {
      setPushError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setPushBusy(false);
    }
  }

  return (
    <section className="qb-main">
      <h2>Data Transfer</h2>
      <Card>
        <p className="qb-muted">
          Hier stehen jetzt beide Richtungen zur Verfuegung: Daten von einer anderen Instanz abrufen oder die aktuellen
          Daten aktiv an eine andere Instanz hochladen.
        </p>
        <p className="qb-muted">
          Fuer beide Richtungen brauchst du ein SuperAdmin-Token des jeweils anderen Systems.
        </p>
        <div className="qb-inline">
          <Button type="button" variant="secondary" onClick={() => void copyCurrentToken()}>
            Eigenes aktuelles Token kopieren
          </Button>
          {copyState ? <span className="qb-muted">{copyState}</span> : null}
        </div>
      </Card>

      <Card>
        <h3 className="qb-card-title">Daten abrufen</h3>
        <p className="qb-muted">
          Die aktuelle Instanz zieht Daten aktiv vom Quellsystem. Das ist der richtige Weg fuer lokale Backups vom
          Live-System, auch wenn dein lokales System nicht von aussen erreichbar ist.
        </p>
        <form onSubmit={onPullSubmit} style={{ display: "grid", gap: 12 }}>
          <label style={{ display: "grid", gap: 6 }}>
            <span className="qb-muted">Quell-URL</span>
            <TextInput
              type="url"
              placeholder="https://questboard.example.com"
              value={sourceBaseURL}
              onChange={(e) => setSourceBaseURL(e.target.value)}
              required
            />
          </label>
          <label style={{ display: "grid", gap: 6 }}>
            <span className="qb-muted">Token</span>
            <TextInput
              type="password"
              placeholder="Bearer-Token der Quellinstanz"
              value={sourceToken}
              onChange={(e) => setSourceToken(e.target.value)}
              required
            />
          </label>
          <div style={{ display: "grid", gap: 6 }}>
            <span className="qb-muted">Bereiche</span>
            <div className="qb-inline">
              {TRANSFER_SECTIONS.map((section) => (
                <Button
                  key={section.key}
                  type="button"
                  variant={selectedSections.includes(section.key) ? "primary" : "secondary"}
                  onClick={() => toggleSection(section.key)}
                >
                  {section.label}
                </Button>
              ))}
            </div>
          </div>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
            <Button type="submit" variant="primary" disabled={pullBusy}>
              {pullBusy ? "Abruf laeuft..." : "Daten vom Quellsystem abrufen"}
            </Button>
          </div>
        </form>
      </Card>

      {pullError ? <p className="qb-error">{pullError}</p> : null}

      {pullResult ? (
        <Card>
          <h3 className="qb-card-title">Abruf Ergebnis</h3>
          <p className="qb-muted">
            Manifest Version {pullResult.manifest.version}, {pullResult.chunksFetched} Chunks verarbeitet.
          </p>
          <p className="qb-muted">Bereiche: {pullResult.sections.join(", ")}</p>
          <pre style={{ whiteSpace: "pre-wrap", margin: 0 }}>{JSON.stringify(pullResult.importResult, null, 2)}</pre>
        </Card>
      ) : null}

      <Card>
        <h3 className="qb-card-title">Daten hochladen</h3>
        <p className="qb-muted">
          Die aktuelle Instanz schiebt ihre Daten aktiv an ein Zielsystem. Das ist hilfreich, wenn das Zielsystem
          erreichbar ist und du Daten bewusst dorthin uebertragen willst.
        </p>
        <form onSubmit={onPushSubmit} style={{ display: "grid", gap: 12 }}>
          <label style={{ display: "grid", gap: 6 }}>
            <span className="qb-muted">Ziel-URL</span>
            <TextInput
              type="url"
              placeholder="https://questboard.example.com"
              value={targetBaseURL}
              onChange={(e) => setTargetBaseURL(e.target.value)}
              required
            />
          </label>
          <label style={{ display: "grid", gap: 6 }}>
            <span className="qb-muted">Ziel-Token</span>
            <TextInput
              type="password"
              placeholder="Bearer-Token der Zielinstanz"
              value={targetToken}
              onChange={(e) => setTargetToken(e.target.value)}
              required
            />
          </label>
          <div style={{ display: "grid", gap: 6 }}>
            <span className="qb-muted">Bereiche</span>
            <div className="qb-inline">
              {TRANSFER_SECTIONS.map((section) => (
                <Button
                  key={`push-${section.key}`}
                  type="button"
                  variant={selectedSections.includes(section.key) ? "primary" : "secondary"}
                  onClick={() => toggleSection(section.key)}
                >
                  {section.label}
                </Button>
              ))}
            </div>
          </div>
          <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
            <Button type="submit" variant="primary" disabled={pushBusy}>
              {pushBusy ? "Upload laeuft..." : "Daten an Zielsystem hochladen"}
            </Button>
          </div>
        </form>
      </Card>

      {pushError ? <p className="qb-error">{pushError}</p> : null}

      {pushResult ? (
        <Card>
          <h3 className="qb-card-title">Upload Ergebnis</h3>
          <p className="qb-muted">
            Manifest Version {pushResult.manifest.version}, {pushResult.chunksSent} Chunks uebertragen.
          </p>
          <p className="qb-muted">Bereiche: {pushResult.sections.join(", ")}</p>
          <pre style={{ whiteSpace: "pre-wrap", margin: 0 }}>{JSON.stringify(pushResult.importResult, null, 2)}</pre>
        </Card>
      ) : null}
    </section>
  );
}
