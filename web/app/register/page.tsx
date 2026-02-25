"use client";

import { FormEvent, Suspense, useState } from "react";
import { useSearchParams } from "next/navigation";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { TextInput } from "../_components/ui/Input";

function RegisterByInviteContent() {
  const params = useSearchParams();
  const urlToken = params.get("token") ?? "";

  const [token, setToken] = useState(urlToken);
  const [username, setUsername] = useState("");
  const [pw1, setPw1] = useState("");
  const [pw2, setPw2] = useState("");
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);
    if (!token.trim()) return setError("Invite-Token fehlt");
    if (!username.trim()) return setError("Username fehlt");
    if (pw1.length < 8) return setError("Passwort zu kurz (min. 8)");
    if (pw1 !== pw2) return setError("Passwoerter stimmen nicht ueberein");

    const res = await fetch("/api/register-by-invite", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: token.trim(), username: username.trim(), password: pw1 })
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      setError(`Registrierung fehlgeschlagen (${res.status}) ${body}`);
      return;
    }
    setDone(true);
  }

  return (
    <main className="qb-main">
      <h1>Registrierung per Invite</h1>
      <Card>
        {done ? (
          <p>
            Registrierung erfolgreich. <a href="/login">Zum Login</a>
          </p>
        ) : (
          <form className="qb-form" onSubmit={submit}>
            <TextInput placeholder="Invite Token" value={token} onChange={(e) => setToken(e.target.value)} />
            <TextInput placeholder="Username" value={username} onChange={(e) => setUsername(e.target.value)} />
            <TextInput type="password" placeholder="Passwort" value={pw1} onChange={(e) => setPw1(e.target.value)} />
            <TextInput type="password" placeholder="Passwort wiederholen" value={pw2} onChange={(e) => setPw2(e.target.value)} />
            <Button type="submit" variant="primary">Registrieren</Button>
          </form>
        )}
      </Card>
      {error ? <p className="qb-error">{error}</p> : null}
    </main>
  );
}

export default function RegisterByInvitePage() {
  return (
    <Suspense fallback={<main className="qb-main"><h1>Loading...</h1></main>}>
      <RegisterByInviteContent />
    </Suspense>
  );
}

