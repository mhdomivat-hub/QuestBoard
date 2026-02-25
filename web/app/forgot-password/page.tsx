"use client";

import { FormEvent, useState } from "react";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { TextInput } from "../_components/ui/Input";

export default function ForgotPasswordPage() {
  const [username, setUsername] = useState("");
  const [note, setNote] = useState("");
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const res = await fetch("/api/password-reset/request", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, note: note || null })
    });

    if (!res.ok) {
      setError(`Request failed (${res.status})`);
      return;
    }

    setDone(true);
  }

  return (
    <main className="qb-main">
      <h1>Passwort vergessen</h1>
      <Card>
        {done ? (
          <p className="qb-muted">Wenn der User existiert, kann ein Admin den Reset freigeben.</p>
        ) : (
          <form onSubmit={submit} className="qb-form">
            <TextInput placeholder="Username" value={username} onChange={(e) => setUsername(e.target.value)} />
            <TextInput placeholder="Optional: Discord/Notiz" value={note} onChange={(e) => setNote(e.target.value)} />
            <Button type="submit" variant="primary">Reset anfragen</Button>
          </form>
        )}
      </Card>
      {error ? <p className="qb-error">{error}</p> : null}
    </main>
  );
}
