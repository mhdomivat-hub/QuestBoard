import React from "react";

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="qb-main">
      <h1>Admin</h1>
      <nav className="qb-nav">
        <a className="qb-nav-link" href="/admin/password-resets">Password Resets</a>
        <a className="qb-nav-link" href="/admin/retention">Retention</a>
        <a className="qb-nav-link" href="/admin/audit">Audit Log</a>
        <a className="qb-nav-link" href="/admin/data-transfer">Data Transfer</a>
      </nav>
      {children}
    </main>
  );
}
