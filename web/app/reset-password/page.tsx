"use client";

import { Suspense, FormEvent, useState } from "react";
import { useSearchParams } from "next/navigation";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { TextInput } from "../_components/ui/Input";

function ResetPasswordContent() {
  const params = useSearchParams();
  const token = params.get("token") ?? "";

  const [pw1, setPw1] = useState("");
  const [pw2, setPw2] = useState("");
  const [done, setDone] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError(null);

    if (!token) return setError("Token fehlt");
    if (pw1.length < 8) return setError("Passwort zu kurz (min 8)");
    if (pw1 !== pw2) return setError("Passwoerter stimmen nicht ueberein");

    const res = await fetch("/api/password-reset/confirm", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token, newPassword: pw1 })
    });

    if (!res.ok) {
      const text = await res.text().catch(() => "");
      setError(`Reset failed (${res.status}) ${text}`);
      return;
    }

    setDone(true);
  }

  return (
    <main className="qb-main">
      <h1>Neues Passwort setzen</h1>
      <Card>
        {done ? (
          <p><a href="/login">Zum Login</a></p>
        ) : (
          <form onSubmit={submit} className="qb-form">
            <TextInput value={token} readOnly placeholder="Token" />
            <TextInput type="password" placeholder="Neues Passwort" value={pw1} onChange={(e) => setPw1(e.target.value)} />
            <TextInput type="password" placeholder="Passwort wiederholen" value={pw2} onChange={(e) => setPw2(e.target.value)} />
            <Button type="submit" variant="primary">Speichern</Button>
          </form>
        )}
      </Card>
      {error ? <p className="qb-error">{error}</p> : null}
    </main>
  );
}

export default function ResetPasswordPage() {
  return (
    <Suspense fallback={<main className="qb-main"><h1>Loading...</h1></main>}>
      <ResetPasswordContent />
    </Suspense>
  );
}
