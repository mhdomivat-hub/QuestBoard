"use client";

import { FormEvent, useEffect, useState } from "react";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { SelectInput, TextArea, TextInput } from "../../_components/ui/Input";
import { statusLabel } from "../../_components/ui/statusLabels";

type QuestStatus = "OPEN" | "IN_PROGRESS" | "DONE" | "ARCHIVED";
type UserRole = "guest" | "member" | "admin" | "superAdmin";

const statuses: QuestStatus[] = ["OPEN", "IN_PROGRESS", "DONE", "ARCHIVED"];

export default function NewQuestPage() {
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [handoverInfo, setHandoverInfo] = useState("");
  const [status, setStatus] = useState<QuestStatus>("OPEN");
  const [isPrioritized, setIsPrioritized] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [role, setRole] = useState<UserRole | null>(null);

  useEffect(() => {
    async function loadMe() {
      const res = await fetch("/api/me", { cache: "no-store" });
      if (res.ok) {
        const me = await res.json();
        const meRole = me.role as UserRole;
        setRole(meRole);
        if (meRole === "guest") {
          window.location.href = "/quests";
        }
      }
    }
    loadMe();
  }, []);

  const canAdmin = role === "admin" || role === "superAdmin";

  async function createQuest(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);

    try {
      const payload = canAdmin
        ? { title, description, handoverInfo: handoverInfo || null, status, isPrioritized }
        : { title, description, handoverInfo: handoverInfo || null, status: "OPEN" };

      const res = await fetch("/api/quests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        const txt = await res.text().catch(() => "");
        setError(`Create failed (${res.status}) ${txt}`);
        return;
      }

      const created = await res.json();
      if (!created?.id) {
        setError("Create failed: response has no id");
        return;
      }

      window.location.href = `/quests/${created.id}`;
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="qb-main">
      <h1>Neue Quest erstellen</h1>
      <Card>
        {!canAdmin ? <p className="qb-muted">Neue Quests werden nach Erstellung erst durch Admins freigegeben.</p> : null}
        <form onSubmit={createQuest} className="qb-form">
          <TextInput placeholder="Titel" value={title} onChange={(e) => setTitle(e.target.value)} required />
          <TextArea placeholder="Beschreibung" value={description} onChange={(e) => setDescription(e.target.value)} rows={4} required />
          <TextInput
            placeholder="Abzugeben bei (Wo und bei wem)"
            value={handoverInfo}
            onChange={(e) => setHandoverInfo(e.target.value)}
          />
          {canAdmin ? (
            <>
              <SelectInput value={status} onChange={(e) => setStatus(e.target.value as QuestStatus)}>
                {statuses.map((s) => (
                  <option key={s} value={s}>{statusLabel(s)}</option>
                ))}
              </SelectInput>
              <label className="qb-inline" style={{ alignItems: "center" }}>
                <input
                  type="checkbox"
                  checked={isPrioritized}
                  onChange={(e) => setIsPrioritized(e.target.checked)}
                />
                <span>Quest priorisieren</span>
              </label>
            </>
          ) : null}
          <Button type="submit" variant="primary" disabled={submitting}>
            {submitting ? "Speichert..." : "Quest anlegen"}
          </Button>
        </form>
      </Card>
      {error ? <p className="qb-error">{error}</p> : null}
    </main>
  );
}
