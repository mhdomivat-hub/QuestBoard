"use client";

import { useState } from "react";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextInput } from "../../_components/ui/Input";

type CleanupResponse = {
  dryRun: boolean;
  olderThanDays: number;
  cutoff: string;
  candidateCount: number;
  deletedCount: number;
};

type SelectedCleanupTargetResult = {
  key: string;
  label: string;
  candidateCount: number;
  deletedCount: number;
};

type SelectedCleanupResponse = {
  dryRun: boolean;
  targets: SelectedCleanupTargetResult[];
  totalCandidateCount: number;
  totalDeletedCount: number;
};

type CleanupTargetOption = {
  key: string;
  label: string;
  description: string;
};

const cleanupOptions: CleanupTargetOption[] = [
  {
    key: "QUEST_CONTRIBUTIONS",
    label: "Quest Contributions",
    description: "Loescht alle Contributions. Quests und Requirements bleiben erhalten."
  },
  {
    key: "BLUEPRINT_CRAFTERS",
    label: "Blueprint Crafter-Zuordnungen",
    description: "Loescht nur, wer was craften kann. Die Blueprint-Hierarchie bleibt erhalten."
  },
  {
    key: "INVITES",
    label: "Invites",
    description: "Loescht alle offenen, verbrauchten und widerrufenen Invites."
  },
  {
    key: "PASSWORD_RESETS",
    label: "Password Reset Requests + Tokens",
    description: "Loescht alle offenen und historischen Passwort-Reset-Daten."
  },
  {
    key: "USERNAME_CHANGE_REQUESTS",
    label: "Username Change Requests",
    description: "Loescht alle Username-Aenderungsanfragen."
  }
];

export default function AdminRetentionPage() {
  const [olderThanDays, setOlderThanDays] = useState(365);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<CleanupResponse | null>(null);
  const [busy, setBusy] = useState(false);

  const [selectedTargets, setSelectedTargets] = useState<string[]>(["QUEST_CONTRIBUTIONS", "BLUEPRINT_CRAFTERS"]);
  const [selectedCleanupResult, setSelectedCleanupResult] = useState<SelectedCleanupResponse | null>(null);
  const [selectedCleanupBusy, setSelectedCleanupBusy] = useState(false);

  async function runCleanup(dryRun: boolean) {
    setBusy(true);
    setError(null);
    setResult(null);
    try {
      const res = await fetch("/api/admin/retention/quests/cleanup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ dryRun, olderThanDays })
      });
      const text = await res.text();
      if (!res.ok) {
        setError(`Cleanup failed (${res.status}) ${text}`);
        return;
      }
      setResult(JSON.parse(text) as CleanupResponse);
    } finally {
      setBusy(false);
    }
  }

  function toggleTarget(key: string) {
    setSelectedTargets((prev) =>
      prev.includes(key) ? prev.filter((item) => item !== key) : [...prev, key]
    );
  }

  async function runSelectedCleanup(dryRun: boolean) {
    setSelectedCleanupBusy(true);
    setError(null);
    setSelectedCleanupResult(null);
    try {
      if (selectedTargets.length === 0) {
        setError("Bitte mindestens einen Cleanup-Typ auswaehlen.");
        return;
      }

      if (!dryRun) {
        const confirmed = window.confirm(
          `Folgende Eintraege werden geloescht: ${selectedTargets.join(", ")}. Fortfahren?`
        );
        if (!confirmed) return;
      }

      const res = await fetch("/api/admin/retention/selected-cleanup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ dryRun, targets: selectedTargets })
      });
      const text = await res.text();
      if (!res.ok) {
        setError(`Selected cleanup failed (${res.status}) ${text}`);
        return;
      }
      setSelectedCleanupResult(JSON.parse(text) as SelectedCleanupResponse);
    } finally {
      setSelectedCleanupBusy(false);
    }
  }

  return (
    <section className="qb-main">
      <h2>Quest Retention Cleanup</h2>
      <Card>
        <p className="qb-muted">Loescht Quests, die auf DONE/ARCHIVED oder geloescht gesetzt wurden und aelter als X Tage sind.</p>
        <div className="qb-form">
          <label htmlFor="days">Aelter als (Tage)</label>
          <TextInput
            id="days"
            type="number"
            min={1}
            value={olderThanDays}
            onChange={(e) => setOlderThanDays(Number(e.target.value))}
          />
          <div className="qb-inline">
            <Button type="button" variant="secondary" onClick={() => runCleanup(true)} disabled={busy}>Dry Run</Button>
            <Button type="button" variant="danger" onClick={() => runCleanup(false)} disabled={busy}>Execute Delete</Button>
          </div>
        </div>
      </Card>

      <Card>
        <h3 className="qb-card-title">Wipe Cleanup</h3>
        <p className="qb-muted">Loescht gezielt Fortschritts- und Betriebsdaten, ohne Stammdaten wie Quests, Requirements oder Blueprint-Struktur zu entfernen.</p>
        <div className="qb-grid">
          {cleanupOptions.map((option) => (
            <label key={option.key} className="qb-inline" style={{ alignItems: "flex-start", gap: 12 }}>
              <input
                type="checkbox"
                checked={selectedTargets.includes(option.key)}
                onChange={() => toggleTarget(option.key)}
              />
              <div>
                <strong>{option.label}</strong>
                <div className="qb-muted">{option.description}</div>
              </div>
            </label>
          ))}
        </div>
        <div className="qb-inline" style={{ marginTop: 16 }}>
          <Button type="button" variant="secondary" onClick={() => runSelectedCleanup(true)} disabled={selectedCleanupBusy}>
            Dry Run
          </Button>
          <Button type="button" variant="danger" onClick={() => runSelectedCleanup(false)} disabled={selectedCleanupBusy}>
            Ausgewaehlte Daten loeschen
          </Button>
        </div>
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}
      {result ? (
        <Card>
          <div>Mode: {result.dryRun ? "Dry Run" : "Execute"}</div>
          <div>olderThanDays: {result.olderThanDays}</div>
          <div>cutoff: {result.cutoff}</div>
          <div>candidateCount: {result.candidateCount}</div>
          <div>deletedCount: {result.deletedCount}</div>
        </Card>
      ) : null}
      {selectedCleanupResult ? (
        <Card>
          <div>Mode: {selectedCleanupResult.dryRun ? "Dry Run" : "Execute"}</div>
          <div>Total candidateCount: {selectedCleanupResult.totalCandidateCount}</div>
          <div>Total deletedCount: {selectedCleanupResult.totalDeletedCount}</div>
          <div className="qb-grid" style={{ marginTop: 12 }}>
            {selectedCleanupResult.targets.map((target) => (
              <div key={target.key} className="qb-inline" style={{ justifyContent: "space-between" }}>
                <strong>{target.label}</strong>
                <span className="qb-muted">{target.deletedCount}/{target.candidateCount}</span>
              </div>
            ))}
          </div>
        </Card>
      ) : null}
    </section>
  );
}
