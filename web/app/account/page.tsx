"use client";

import { FormEvent, useEffect, useState } from "react";
import Button from "../_components/ui/Button";
import Card from "../_components/ui/Card";
import { TextInput } from "../_components/ui/Input";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type UsernameChangeRequest = {
  id: string;
  desiredUsername: string;
  status: "PENDING" | "APPROVED" | "REJECTED";
  createdAt?: string | null;
  reviewedAt?: string | null;
};
type AccountResponse = {
  userId: string;
  username: string;
  role: UserRole;
  pendingUsernameChangeRequest: UsernameChangeRequest | null;
};

export default function AccountPage() {
  const [account, setAccount] = useState<AccountResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordBusy, setPasswordBusy] = useState(false);
  const [passwordMessage, setPasswordMessage] = useState<string | null>(null);

  const [desiredUsername, setDesiredUsername] = useState("");
  const [usernameBusy, setUsernameBusy] = useState(false);
  const [usernameMessage, setUsernameMessage] = useState<string | null>(null);

  async function loadAccount() {
    setLoading(true);
    setError(null);
    const res = await fetch("/api/account", { cache: "no-store" });
    if (res.status === 401) {
      window.location.href = "/login";
      return;
    }
    if (!res.ok) {
      setError(`Account load failed (${res.status})`);
      setLoading(false);
      return;
    }
    const body = (await res.json()) as AccountResponse;
    setAccount(body);
    setDesiredUsername(body.username);
    setLoading(false);
  }

  useEffect(() => {
    loadAccount();
  }, []);

  async function submitPassword(e: FormEvent) {
    e.preventDefault();
    setPasswordMessage(null);

    if (newPassword !== confirmPassword) {
      setPasswordMessage("Die neuen Passwoerter stimmen nicht ueberein.");
      return;
    }

    setPasswordBusy(true);
    try {
      const res = await fetch("/api/account/password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ currentPassword, newPassword })
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setPasswordMessage(`Passwortwechsel fehlgeschlagen (${res.status}) ${body}`);
        return;
      }

      window.location.href = "/login";
    } finally {
      setPasswordBusy(false);
    }
  }

  async function submitUsernameRequest(e: FormEvent) {
    e.preventDefault();
    setUsernameMessage(null);
    setUsernameBusy(true);

    try {
      const res = await fetch("/api/account/username-change-requests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ desiredUsername })
      });

      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setUsernameMessage(`Username-Anfrage fehlgeschlagen (${res.status}) ${body}`);
        return;
      }

      setUsernameMessage("Username-Aenderung wurde zur Freigabe an den SuperAdmin gesendet.");
      await loadAccount();
    } finally {
      setUsernameBusy(false);
    }
  }

  if (loading) {
    return <main className="qb-main"><p className="qb-muted">Account wird geladen...</p></main>;
  }

  return (
    <main className="qb-main">
      <h1>Account</h1>
      {error ? <p className="qb-error">{error}</p> : null}

      <Card>
        <h2>Profil</h2>
        <p><strong>Username:</strong> {account?.username}</p>
        <p><strong>Rolle:</strong> {account?.role}</p>
      </Card>

      <Card>
        <h2>Passwort aendern</h2>
        <form className="qb-form" onSubmit={submitPassword}>
          <TextInput type="password" placeholder="Aktuelles Passwort" autoComplete="current-password" value={currentPassword} onChange={(e) => setCurrentPassword(e.target.value)} />
          <TextInput type="password" placeholder="Neues Passwort" autoComplete="new-password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} />
          <TextInput type="password" placeholder="Neues Passwort wiederholen" autoComplete="new-password" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} />
          <Button type="submit" variant="primary" disabled={passwordBusy}>
            {passwordBusy ? "Speichere..." : "Passwort aendern"}
          </Button>
        </form>
        {passwordMessage ? <p className={passwordMessage.includes("fehlgeschlagen") ? "qb-error" : "qb-muted"}>{passwordMessage}</p> : null}
      </Card>

      <Card>
        <h2>Username aendern</h2>
        <p className="qb-muted">Die Username-Aenderung wird erst aktiv, wenn ein SuperAdmin sie freigibt.</p>
        {account?.pendingUsernameChangeRequest ? (
          <p className="qb-muted">Offene Anfrage: {account.pendingUsernameChangeRequest.desiredUsername}</p>
        ) : null}
        <form className="qb-form" onSubmit={submitUsernameRequest}>
          <TextInput
            placeholder="Gewuenschter neuer Username"
            value={desiredUsername}
            onChange={(e) => setDesiredUsername(e.target.value)}
            disabled={Boolean(account?.pendingUsernameChangeRequest) || usernameBusy}
          />
          <Button type="submit" variant="secondary" disabled={Boolean(account?.pendingUsernameChangeRequest) || usernameBusy}>
            {usernameBusy ? "Sende..." : "Username-Aenderung beantragen"}
          </Button>
        </form>
        {usernameMessage ? <p className={usernameMessage.includes("fehlgeschlagen") ? "qb-error" : "qb-muted"}>{usernameMessage}</p> : null}
      </Card>
    </main>
  );
}
