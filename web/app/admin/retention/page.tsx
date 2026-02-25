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

export default function AdminRetentionPage() {
  const [olderThanDays, setOlderThanDays] = useState(365);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<CleanupResponse | null>(null);
  const [busy, setBusy] = useState(false);

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
    </section>
  );
}
