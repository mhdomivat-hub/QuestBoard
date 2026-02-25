"use client";

import { FormEvent, useState } from "react";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { TextInput } from "../_components/ui/Input";

export default function LoginPage() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);

    const res = await fetch("/api/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username, password })
    });

    if (!res.ok) {
      setError(`Login failed (${res.status})`);
      return;
    }

    window.location.href = "/";
  }

  return (
    <main className="qb-main">
      <h1>Login</h1>
      <Card>
        <form onSubmit={submit} className="qb-form">
          <TextInput
            placeholder="Username"
            autoComplete="username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
          />
          <TextInput
            type="password"
            placeholder="Passwort"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          <Button type="submit" variant="primary">Einloggen</Button>
        </form>
      </Card>
      <p><a href="/register">Invite erhalten? Jetzt registrieren</a></p>
      <p><a href="/forgot-password">Passwort vergessen?</a></p>
      {error ? <p className="qb-error">{error}</p> : null}
    </main>
  );
}
