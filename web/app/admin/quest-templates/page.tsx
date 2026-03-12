"use client";

import { FormEvent, useEffect, useState } from "react";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";
import { TextArea, TextInput } from "../../_components/ui/Input";

type TemplateSummary = {
  id: string;
  title: string;
  description: string;
  handoverInfo?: string | null;
  requirementCount: number;
  createdAt?: string | null;
};

type QuestResponse = { id: string };

export default function QuestTemplatesPage() {
  const [templates, setTemplates] = useState<TemplateSummary[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [handoverInfo, setHandoverInfo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function loadTemplates() {
    setLoading(true);
    const res = await fetch("/api/admin/quest-templates", { cache: "no-store" });
    if (!res.ok) {
      throw new Error(`Templates load failed (${res.status})`);
    }
    setTemplates((await res.json()) as TemplateSummary[]);
    setLoading(false);
  }

  useEffect(() => {
    loadTemplates().catch((e) => {
      setError(e instanceof Error ? e.message : "Unknown error");
      setLoading(false);
    });
  }, []);

  async function createTemplate(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const res = await fetch("/api/admin/quest-templates", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description, handoverInfo: handoverInfo || null })
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Template erstellen fehlgeschlagen (${res.status}) ${text}`);
      return;
    }
    const created = (await res.json()) as { id: string };
    window.location.href = `/admin/quest-templates/${created.id}`;
  }

  async function createQuestFromTemplate(templateId: string) {
    setError(null);
    const res = await fetch(`/api/admin/quest-templates/${templateId}/create-quest`, { method: "POST" });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Quest aus Template fehlgeschlagen (${res.status}) ${text}`);
      return;
    }
    const quest = (await res.json()) as QuestResponse;
    window.location.href = `/quests/${quest.id}`;
  }

  async function deleteTemplate(templateId: string) {
    if (!window.confirm("Template wirklich loeschen?")) return;
    setError(null);
    const res = await fetch(`/api/admin/quest-templates/${templateId}`, { method: "DELETE" });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Template loeschen fehlgeschlagen (${res.status}) ${text}`);
      return;
    }
    await loadTemplates();
  }

  return (
    <section className="qb-grid">
      <Card>
        <h2 className="qb-card-title">Neues Quest-Template</h2>
        <form className="qb-form" onSubmit={createTemplate}>
          <TextInput placeholder="Titel" value={title} onChange={(e) => setTitle(e.target.value)} required />
          <TextInput placeholder="Abzugeben bei" value={handoverInfo} onChange={(e) => setHandoverInfo(e.target.value)} />
          <TextArea placeholder="Beschreibung" value={description} onChange={(e) => setDescription(e.target.value)} rows={4} required />
          <Button type="submit" variant="primary">Template erstellen</Button>
        </form>
      </Card>

      <Card>
        <h2 className="qb-card-title">Vorhandene Templates</h2>
        {loading ? <p className="qb-muted">Lade Templates...</p> : null}
        {error ? <p className="qb-error">{error}</p> : null}
        {!loading && templates.length === 0 ? <p className="qb-muted">Noch keine Templates vorhanden.</p> : null}
        <div className="qb-grid">
          {templates.map((template) => (
            <Card key={template.id}>
              <div className="qb-inline" style={{ justifyContent: "space-between" }}>
                <strong><a href={`/admin/quest-templates/${template.id}`}>{template.title}</a></strong>
                <span className="qb-muted">{template.requirementCount} Requirements</span>
              </div>
              <p className="qb-muted">{template.description}</p>
              <p className="qb-muted">Abzugeben bei: {template.handoverInfo?.trim() ? template.handoverInfo : "Nicht gesetzt"}</p>
              <div className="qb-inline" style={{ gap: 12 }}>
                <Button type="button" variant="secondary" onClick={() => { window.location.href = `/admin/quest-templates/${template.id}`; }}>
                  Details
                </Button>
                <Button type="button" variant="primary" onClick={() => createQuestFromTemplate(template.id)}>
                  Quest starten
                </Button>
                <Button type="button" variant="danger" onClick={() => deleteTemplate(template.id)}>
                  Loeschen
                </Button>
              </div>
            </Card>
          ))}
        </div>
      </Card>
    </section>
  );
}
