import React from "react";
import { cookies } from "next/headers";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";

async function loadRole(): Promise<string | null> {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return null;

  try {
    const res = await fetch(`${API_BASE}/me`, {
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store"
    });
    if (!res.ok) return null;
    const me = (await res.json()) as { role?: string };
    return me.role ?? null;
  } catch {
    return null;
  }
}

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const role = await loadRole();
  const isSuperAdmin = role === "superAdmin";

  return (
    <main className="qb-main">
      <h1>Admin</h1>
      <nav className="qb-nav">
        <a className="qb-nav-link" href="/admin/users">Users</a>
        <a className="qb-nav-link" href="/admin/invites">Invites</a>
        <a className="qb-nav-link" href="/admin/password-resets">Password Resets</a>
        <a className="qb-nav-link" href="/admin/retention">Retention</a>
        <a className="qb-nav-link" href="/admin/quest-templates">Quest Templates</a>
        <a className="qb-nav-link" href="/admin/audit">Audit Log</a>
        {isSuperAdmin ? <a className="qb-nav-link" href="/admin/data-transfer">Data Transfer</a> : null}
      </nav>
      {children}
    </main>
  );
}
