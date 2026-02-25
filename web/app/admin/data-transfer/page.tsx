"use client";

import { useState } from "react";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";

type ImportResult = Record<string, number>;

type ExportManifest = {
  version: number;
  generatedAt: string;
  counts: {
    users: number;
    quests: number;
    requirements: number;
    contributions: number;
    passwordResetRequests: number;
    passwordResetTokens: number;
    apiTokens: number;
    auditEvents: number;
  };
};

const EXPORT_CHUNK_SIZE = 500;
const SECTIONS = [
  { section: "users", key: "users" },
  { section: "quests", key: "quests" },
  { section: "requirements", key: "requirements" },
  { section: "contributions", key: "contributions" },
  { section: "passwordResetRequests", key: "passwordResetRequests" },
  { section: "passwordResetTokens", key: "passwordResetTokens" },
  { section: "apiTokens", key: "apiTokens" },
  { section: "auditEvents", key: "auditEvents" }
] as const;

function sumResults(current: ImportResult, next: ImportResult): ImportResult {
  const out: ImportResult = { ...current };
  for (const [k, v] of Object.entries(next)) out[k] = (out[k] ?? 0) + (typeof v === "number" ? v : 0);
  return out;
}

export default function AdminDataTransferPage() {
  const [error, setError] = useState<string | null>(null);
  const [busyExport, setBusyExport] = useState(false);
  const [busyImport, setBusyImport] = useState(false);
  const [lastResult, setLastResult] = useState<ImportResult | null>(null);
  const [lastExportSummary, setLastExportSummary] = useState<string | null>(null);

  function downloadJsonFile(data: unknown, fileName: string) {
    const json = JSON.stringify(data, null, 2);
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = fileName;
    link.click();
    URL.revokeObjectURL(url);
  }

  async function exportData() {
    setError(null);
    setLastExportSummary(null);
    setBusyExport(true);
    try {
      const manifestRes = await fetch("/api/admin/data/export/manifest", { cache: "no-store" });
      if (!manifestRes.ok) {
        setError(`Manifest load failed (${manifestRes.status})`);
        return;
      }
      const manifest = (await manifestRes.json()) as ExportManifest;

      const ts = new Date().toISOString().replace(/[:.]/g, "-");
      downloadJsonFile(manifest, `questboard-export-${ts}-manifest.json`);

      let fileCount = 1;
      for (const item of SECTIONS) {
        const total = manifest.counts[item.key];
        if (!total || total <= 0) continue;
        const chunkCount = Math.ceil(total / EXPORT_CHUNK_SIZE);
        for (let chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
          const offset = chunkIndex * EXPORT_CHUNK_SIZE;
          const url = `/api/admin/data/export/${item.section}?limit=${EXPORT_CHUNK_SIZE}&offset=${offset}`;
          const res = await fetch(url, { cache: "no-store" });
          if (!res.ok) {
            setError(`Export chunk failed (${item.section} ${chunkIndex + 1}/${chunkCount}, HTTP ${res.status})`);
            return;
          }
          const data = await res.json();
          downloadJsonFile(data, `questboard-export-${ts}-${item.section}-${String(chunkIndex + 1).padStart(4, "0")}.json`);
          fileCount += 1;
        }
      }
      setLastExportSummary(`${fileCount} Dateien exportiert (inkl. Manifest).`);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Export failed");
    } finally {
      setBusyExport(false);
    }
  }

  async function importDataFromFiles(files: FileList) {
    setError(null);
    setLastResult(null);
    setBusyImport(true);
    try {
      const ordered = Array.from(files).sort((a, b) => a.name.localeCompare(b.name));
      let aggregate: ImportResult = {};
      let importedCount = 0;

      for (const file of ordered) {
        if (!file.name.toLowerCase().endsWith(".json")) continue;
        if (file.name.toLowerCase().includes("manifest")) continue;

        const text = await file.text();
        const payload = JSON.parse(text);
        const res = await fetch("/api/admin/data/import", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload)
        });
        if (!res.ok) {
          const body = await res.text().catch(() => "");
          setError(`Import failed (${file.name}, HTTP ${res.status}) ${body}`);
          return;
        }
        const result = (await res.json()) as ImportResult;
        aggregate = sumResults(aggregate, result);
        importedCount += 1;
      }

      if (importedCount === 0) {
        setError("Keine importierbaren JSON-Dateien ausgewaehlt.");
        return;
      }
      setLastResult(aggregate);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Import failed");
    } finally {
      setBusyImport(false);
    }
  }

  return (
    <section className="qb-main">
      <h2>Data Transfer</h2>
      <Card>
        <p className="qb-muted">
          Export erstellt mehrere JSON-Dateien (Manifest + Chunks pro Datentyp), damit grosse Datenmengen stabil
          verarbeitet werden.
        </p>
        <Button type="button" variant="primary" onClick={exportData} disabled={busyExport}>
          {busyExport ? "Export laeuft..." : "Export herunterladen (mehrere Dateien)"}
        </Button>
        {lastExportSummary ? <p className="qb-muted">{lastExportSummary}</p> : null}
      </Card>

      <Card>
        <p className="qb-muted">
          Import akzeptiert mehrere JSON-Dateien. Dateien werden nacheinander verarbeitet. Es werden nur fehlende
          Daten angelegt, bei Konflikten haben Server-Daten Vorrang.
        </p>
        <input
          type="file"
          accept="application/json"
          multiple
          onChange={(e) => {
            const selected = e.target.files;
            if (selected && selected.length > 0) void importDataFromFiles(selected);
          }}
          disabled={busyImport}
        />
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}
      {lastResult ? (
        <Card>
          <h3 className="qb-card-title">Import Ergebnis</h3>
          <pre style={{ whiteSpace: "pre-wrap", margin: 0 }}>{JSON.stringify(lastResult, null, 2)}</pre>
        </Card>
      ) : null}
    </section>
  );
}
