"use client";

import { FormEvent, useEffect, useState } from "react";
import { useParams } from "next/navigation";
import Button from "../../../_components/ui/Button";
import Card from "../../../_components/ui/Card";
import { TextArea, TextInput } from "../../../_components/ui/Input";

type TemplateRequirement = {
  id: string;
  templateId: string;
  itemName: string;
  qtyNeeded: number;
  unit: string;
};

type TemplateDetail = {
  id: string;
  title: string;
  description: string;
  handoverInfo?: string | null;
  requirements: TemplateRequirement[];
};

type QuestResponse = { id: string };

export default function QuestTemplateDetailPage() {
  const params = useParams<{ id: string }>();
  const templateId = params.id;

  const [template, setTemplate] = useState<TemplateDetail | null>(null);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [handoverInfo, setHandoverInfo] = useState("");
  const [itemName, setItemName] = useState("");
  const [qtyNeeded, setQtyNeeded] = useState(1);
  const [unit, setUnit] = useState("pcs");
  const [error, setError] = useState<string | null>(null);

  async function loadTemplate() {
    const res = await fetch(`/api/admin/quest-templates/${templateId}`, { cache: "no-store" });
    if (!res.ok) {
      throw new Error(`Template load failed (${res.status})`);
    }
    const data = (await res.json()) as TemplateDetail;
    setTemplate(data);
    setTitle(data.title);
    setDescription(data.description);
    setHandoverInfo(data.handoverInfo ?? "");
  }

  useEffect(() => {
    if (!templateId) return;
    loadTemplate().catch((e) => setError(e instanceof Error ? e.message : "Unknown error"));
  }, [templateId]);

  async function saveTemplate(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const res = await fetch(`/api/admin/quest-templates/${templateId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description, handoverInfo: handoverInfo || null })
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Template speichern fehlgeschlagen (${res.status}) ${text}`);
      return;
    }
    await loadTemplate();
  }

  async function addRequirement(e: FormEvent) {
    e.preventDefault();
    setError(null);
    const res = await fetch(`/api/admin/quest-templates/${templateId}/requirements`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ itemName, qtyNeeded, unit })
    });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Requirement erstellen fehlgeschlagen (${res.status}) ${text}`);
      return;
    }
    setItemName("");
    setQtyNeeded(1);
    setUnit("pcs");
    await loadTemplate();
  }

  async function createQuestFromTemplate() {
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

  async function deleteTemplate() {
    if (!window.confirm("Template wirklich loeschen?")) return;
    setError(null);
    const res = await fetch(`/api/admin/quest-templates/${templateId}`, { method: "DELETE" });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Template loeschen fehlgeschlagen (${res.status}) ${text}`);
      return;
    }
    window.location.href = "/admin/quest-templates";
  }

  return (
    <section className="qb-grid">
      {template ? (
        <Card>
          <div className="qb-inline" style={{ justifyContent: "space-between" }}>
            <strong>{template.title}</strong>
            <div className="qb-inline" style={{ gap: 12 }}>
              <Button type="button" variant="primary" onClick={createQuestFromTemplate}>Quest starten</Button>
              <Button type="button" variant="danger" onClick={deleteTemplate}>Template loeschen</Button>
            </div>
          </div>
          <form className="qb-form" onSubmit={saveTemplate} style={{ marginTop: 12 }}>
            <TextInput placeholder="Titel" value={title} onChange={(e) => setTitle(e.target.value)} required />
            <TextInput placeholder="Abzugeben bei" value={handoverInfo} onChange={(e) => setHandoverInfo(e.target.value)} />
            <TextArea placeholder="Beschreibung" value={description} onChange={(e) => setDescription(e.target.value)} rows={5} required />
            <Button type="submit" variant="primary">Template speichern</Button>
          </form>
        </Card>
      ) : null}

      <Card>
        <h2 className="qb-card-title">Requirement hinzufuegen</h2>
        <form className="qb-form" onSubmit={addRequirement}>
          <TextInput placeholder="Material / Item" value={itemName} onChange={(e) => setItemName(e.target.value)} required />
          <TextInput type="number" min={1} value={qtyNeeded} onChange={(e) => setQtyNeeded(Number(e.target.value))} required />
          <TextInput placeholder="Einheit" value={unit} onChange={(e) => setUnit(e.target.value)} required />
          <Button type="submit" variant="primary">Requirement speichern</Button>
        </form>
      </Card>

      <Card>
        <h2 className="qb-card-title">Requirements</h2>
        {template && template.requirements.length === 0 ? <p className="qb-muted">Noch keine Requirements vorhanden.</p> : null}
        <div className="qb-grid">
          {template?.requirements.map((requirement) => (
            <div key={requirement.id} className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong>{requirement.itemName}</strong>
              <span className="qb-muted">{requirement.qtyNeeded} {requirement.unit}</span>
            </div>
          ))}
        </div>
      </Card>

      {error ? <p className="qb-error">{error}</p> : null}
    </section>
  );
}
