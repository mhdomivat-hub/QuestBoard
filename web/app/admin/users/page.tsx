"use client";

import { useEffect, useMemo, useState } from "react";
import Button from "../../_components/ui/Button";
import Card from "../../_components/ui/Card";

type UserRole = "guest" | "member" | "admin" | "superAdmin";
type AdminUser = {
  id: string;
  username: string;
  role: UserRole;
  isRoleImmutable: boolean;
};

export default function AdminUsersPage() {
  const pageSize = 12;
  const [items, setItems] = useState<AdminUser[]>([]);
  const [myRole, setMyRole] = useState<UserRole | null>(null);
  const [myUserId, setMyUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [draftRoles, setDraftRoles] = useState<Record<string, UserRole>>({});
  const [roleFilter, setRoleFilter] = useState<"all" | UserRole>("all");
  const [page, setPage] = useState(1);

  async function refresh() {
    setError(null);
    const [usersRes, meRes] = await Promise.all([
      fetch("/api/admin/users", { cache: "no-store" }),
      fetch("/api/me", { cache: "no-store" })
    ]);

    if (!usersRes.ok) {
      setError(`Users load failed (${usersRes.status})`);
      return;
    }
    if (meRes.ok) {
      const me = await meRes.json();
      setMyRole((me.role as UserRole | undefined) ?? null);
      setMyUserId((me.userId as string | undefined) ?? null);
    }
    const users = (await usersRes.json()) as AdminUser[];
    setItems(users);
    const nextDrafts: Record<string, UserRole> = {};
    for (const user of users) nextDrafts[user.id] = user.role;
    setDraftRoles(nextDrafts);
  }

  useEffect(() => {
    refresh();
  }, []);

  async function updateRole(userId: string, role: UserRole) {
    setError(null);
    setBusyId(userId);
    try {
      const res = await fetch(`/api/admin/users/${userId}/role`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ role })
      });
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setError(`Role update failed (${res.status}) ${body}`);
        return;
      }
      await refresh();
    } finally {
      setBusyId(null);
    }
  }

  async function deleteUser(userId: string) {
    if (!confirm("User wirklich loeschen? Diese Aktion kann nicht rueckgaengig gemacht werden.")) {
      return;
    }

    setError(null);
    setBusyId(userId);
    try {
      const res = await fetch(`/api/admin/users/${userId}`, { method: "DELETE" });
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setError(`User delete failed (${res.status}) ${body}`);
        return;
      }
      await refresh();
    } finally {
      setBusyId(null);
    }
  }

  const canEditRoles = myRole === "admin" || myRole === "superAdmin";
  const editableRoleOptionsFor = (targetRole: UserRole): UserRole[] => {
    if (myRole === "superAdmin") return ["guest", "member", "admin", "superAdmin"];
    if (myRole === "admin") {
      return targetRole === "guest" || targetRole === "member" ? ["guest", "member"] : [targetRole];
    }
    return [targetRole];
  };
  const canEditTargetRole = (targetRole: UserRole) => {
    if (myRole === "superAdmin") return true;
    if (myRole === "admin") return targetRole === "guest" || targetRole === "member";
    return false;
  };
  const canEditItemRole = (item: AdminUser) => canEditTargetRole(item.role) && !item.isRoleImmutable;
  const roleSortWeight: Record<UserRole, number> = {
    superAdmin: 0,
    admin: 1,
    member: 2,
    guest: 3
  };
  const visibleItems = useMemo(() => {
    const filtered =
      roleFilter === "all" ? items : items.filter((item) => item.role === roleFilter);
    return [...filtered].sort((a, b) => {
      const roleDiff = roleSortWeight[a.role] - roleSortWeight[b.role];
      if (roleDiff !== 0) return roleDiff;
      return a.username.localeCompare(b.username, "de", { sensitivity: "base" });
    });
  }, [items, roleFilter]);
  const totalPages = Math.max(1, Math.ceil(visibleItems.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const pagedItems = useMemo(() => {
    const start = (currentPage - 1) * pageSize;
    return visibleItems.slice(start, start + pageSize);
  }, [visibleItems, currentPage, pageSize]);

  return (
    <section className="qb-main">
      <h2>Users</h2>
      <div className="qb-inline">
        <label className="qb-muted" htmlFor="role-filter">
          Rolle filtern:
        </label>
        <select
          id="role-filter"
          className="qb-input"
          value={roleFilter}
          onChange={(e) => {
            setRoleFilter(e.target.value as "all" | UserRole);
            setPage(1);
          }}
        >
          <option value="all">alle</option>
          <option value="superAdmin">superAdmin</option>
          <option value="admin">admin</option>
          <option value="member">member</option>
          <option value="guest">guest</option>
        </select>
      </div>
      {canEditRoles ? (
        <p className="qb-muted">
          Admin darf nur zwischen guest und member wechseln. SuperAdmin darf alle Rollen verwalten.
        </p>
      ) : (
        <p className="qb-muted">Member/Gast haben keinen Zugriff auf Rollenverwaltung.</p>
      )}
      {error ? <p className="qb-error">{error}</p> : null}

      <div className="qb-grid">
        {pagedItems.map((item) => (
          <Card key={item.id}>
            <div className="qb-inline" style={{ justifyContent: "space-between" }}>
              <strong>{item.username}</strong>
              <span className="qb-muted">{item.role}</span>
            </div>
            {canEditRoles ? (
              <div className="qb-inline">
                <select
                  className="qb-input"
                  value={draftRoles[item.id] ?? item.role}
                  onChange={(e) =>
                    setDraftRoles((prev) => ({ ...prev, [item.id]: e.target.value as UserRole }))
                  }
                  disabled={busyId === item.id || !canEditItemRole(item)}
                >
                  {editableRoleOptionsFor(item.role).map((roleOption) => (
                    <option key={roleOption} value={roleOption}>
                      {roleOption}
                    </option>
                  ))}
                </select>
                <Button
                  variant="secondary"
                  disabled={
                    busyId === item.id ||
                    !canEditItemRole(item) ||
                    (draftRoles[item.id] ?? item.role) === item.role
                  }
                  onClick={() => updateRole(item.id, draftRoles[item.id] ?? item.role)}
                >
                  {busyId === item.id ? "Speichere..." : "Rolle speichern"}
                </Button>
              </div>
            ) : null}
            {item.isRoleImmutable ? (
              <p className="qb-muted">Bootstrap-Admin: Rolle ist gesperrt.</p>
            ) : null}
            {canEditRoles ? (
              <Button
                variant="danger"
                disabled={busyId === item.id || item.id === myUserId}
                onClick={() => deleteUser(item.id)}
              >
                {busyId === item.id ? "Loesche..." : "User loeschen"}
              </Button>
            ) : null}
          </Card>
        ))}
      </div>
      <div className="qb-inline" style={{ justifyContent: "space-between" }}>
        <p className="qb-muted">
          Seite {currentPage} / {totalPages} ({visibleItems.length} User)
        </p>
        <div className="qb-inline">
          <Button
            variant="secondary"
            disabled={currentPage <= 1}
            onClick={() => setPage((prev) => Math.max(1, prev - 1))}
          >
            Zurueck
          </Button>
          <Button
            variant="secondary"
            disabled={currentPage >= totalPages}
            onClick={() => setPage((prev) => Math.min(totalPages, prev + 1))}
          >
            Weiter
          </Button>
        </div>
      </div>
    </section>
  );
}
