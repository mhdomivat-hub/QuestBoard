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
type PendingUsernameChangeRequest = {
  id: string;
  userId: string;
  currentUsername: string;
  desiredUsername: string;
  status: "PENDING" | "APPROVED" | "REJECTED";
  createdAt?: string | null;
  reviewedAt?: string | null;
};

export default function AdminUsersPage() {
  const pageSize = 12;
  const defaultRoleFilters: UserRole[] = ["guest"];
  const [items, setItems] = useState<AdminUser[]>([]);
  const [pendingUsernameRequests, setPendingUsernameRequests] = useState<PendingUsernameChangeRequest[]>([]);
  const [myRole, setMyRole] = useState<UserRole | null>(null);
  const [myUserId, setMyUserId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [usernameRequestBusyId, setUsernameRequestBusyId] = useState<string | null>(null);
  const [draftRoles, setDraftRoles] = useState<Record<string, UserRole>>({});
  const [activeRoleFilters, setActiveRoleFilters] = useState<UserRole[]>(defaultRoleFilters);
  const [page, setPage] = useState(1);

  async function refresh() {
    setError(null);
    const meRes = await fetch("/api/me", { cache: "no-store" });
    let meRole: UserRole | null = null;
    if (meRes.ok) {
      const me = await meRes.json();
      meRole = (me.role as UserRole | undefined) ?? null;
      setMyRole(meRole);
      setMyUserId((me.userId as string | undefined) ?? null);
    }

    const requests = [fetch("/api/admin/users", { cache: "no-store" })];
    if (meRole === "superAdmin") {
      requests.push(fetch("/api/admin/username-change-requests/pending", { cache: "no-store" }));
    }

    const results = await Promise.all(requests);
    const usersRes = results[0];
    if (!usersRes.ok) {
      setError(`Users load failed (${usersRes.status})`);
      return;
    }

    const users = (await usersRes.json()) as AdminUser[];
    setItems(users);
    const nextDrafts: Record<string, UserRole> = {};
    for (const user of users) nextDrafts[user.id] = user.role;
    setDraftRoles(nextDrafts);

    if (meRole === "superAdmin" && results[1]) {
      const pendingRes = results[1];
      if (pendingRes.ok) {
        setPendingUsernameRequests((await pendingRes.json()) as PendingUsernameChangeRequest[]);
      } else {
        setPendingUsernameRequests([]);
        setError(`Username requests load failed (${pendingRes.status})`);
      }
    } else {
      setPendingUsernameRequests([]);
    }
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

  async function handleUsernameRequest(requestId: string, action: "approve" | "reject") {
    setError(null);
    setUsernameRequestBusyId(requestId);
    try {
      const res = await fetch(`/api/admin/username-change-requests/${requestId}/${action}`, {
        method: "POST"
      });
      if (!res.ok) {
        const body = await res.text().catch(() => "");
        setError(`Username request ${action} failed (${res.status}) ${body}`);
        return;
      }
      await refresh();
    } finally {
      setUsernameRequestBusyId(null);
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
  const roleCounts: Record<UserRole, number> = {
    superAdmin: items.filter((item) => item.role === "superAdmin").length,
    admin: items.filter((item) => item.role === "admin").length,
    member: items.filter((item) => item.role === "member").length,
    guest: items.filter((item) => item.role === "guest").length
  };
  const roleSortWeight: Record<UserRole, number> = {
    superAdmin: 0,
    admin: 1,
    member: 2,
    guest: 3
  };
  const visibleItems = useMemo(() => {
    const filterSet = new Set(activeRoleFilters);
    const filtered = items.filter((item) => filterSet.has(item.role));
    return [...filtered].sort((a, b) => {
      const roleDiff = roleSortWeight[a.role] - roleSortWeight[b.role];
      if (roleDiff !== 0) return roleDiff;
      return a.username.localeCompare(b.username, "de", { sensitivity: "base" });
    });
  }, [items, activeRoleFilters]);
  const totalPages = Math.max(1, Math.ceil(visibleItems.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const pagedItems = useMemo(() => {
    const start = (currentPage - 1) * pageSize;
    return visibleItems.slice(start, start + pageSize);
  }, [visibleItems, currentPage, pageSize]);
  const hasExplicitFilters =
    activeRoleFilters.length !== defaultRoleFilters.length ||
    defaultRoleFilters.some((role) => !activeRoleFilters.includes(role));

  function toggleRoleFilter(role: UserRole) {
    setActiveRoleFilters((current) => {
      const next = new Set(current);
      if (next.has(role)) {
        next.delete(role);
      } else {
        next.add(role);
      }

      if (next.size === 0) {
        return [...defaultRoleFilters];
      }

      return (["guest", "member", "admin", "superAdmin"] as UserRole[]).filter((item) => next.has(item));
    });
    setPage(1);
  }

  function resetRoleFilters() {
    setActiveRoleFilters([...defaultRoleFilters]);
    setPage(1);
  }

  return (
    <section className="qb-main">
      <h2>Users</h2>
      <div className="qb-inline">
        <Button type="button" variant={activeRoleFilters.includes("guest") ? "primary" : "secondary"} onClick={() => toggleRoleFilter("guest")}>
          Gast {roleCounts.guest}
        </Button>
        <Button type="button" variant={activeRoleFilters.includes("member") ? "primary" : "secondary"} onClick={() => toggleRoleFilter("member")}>
          Member {roleCounts.member}
        </Button>
        <Button type="button" variant={activeRoleFilters.includes("admin") ? "primary" : "secondary"} onClick={() => toggleRoleFilter("admin")}>
          Admin {roleCounts.admin}
        </Button>
        <Button type="button" variant={activeRoleFilters.includes("superAdmin") ? "primary" : "secondary"} onClick={() => toggleRoleFilter("superAdmin")}>
          SuperAdmin {roleCounts.superAdmin}
        </Button>
        {hasExplicitFilters ? (
          <button type="button" className="qb-nav-link" onClick={resetRoleFilters} style={{ background: "none", border: "none", cursor: "pointer", padding: 0 }}>
            Filter zuruecksetzen
          </button>
        ) : null}
      </div>
      {canEditRoles ? (
        <p className="qb-muted">Admin darf nur zwischen guest und member wechseln. SuperAdmin darf alle Rollen verwalten.</p>
      ) : (
        <p className="qb-muted">Member/Gast haben keinen Zugriff auf Rollenverwaltung.</p>
      )}
      {error ? <p className="qb-error">{error}</p> : null}

      {myRole === "superAdmin" ? (
        <Card>
          <div className="qb-inline" style={{ justifyContent: "space-between" }}>
            <strong>Offene Username-Aenderungen</strong>
            <span className="qb-muted">{pendingUsernameRequests.length}</span>
          </div>
          {pendingUsernameRequests.length === 0 ? (
            <p className="qb-muted">Keine offenen Username-Aenderungen.</p>
          ) : (
            <div className="qb-grid">
              {pendingUsernameRequests.map((item) => (
                <Card key={item.id}>
                  <p><strong>{item.currentUsername}</strong> {"->"} {item.desiredUsername}</p>
                  <p className="qb-muted">Beantragt: {item.createdAt ? new Date(item.createdAt).toLocaleString("de-DE") : "unbekannt"}</p>
                  <div className="qb-inline">
                    <Button variant="primary" disabled={usernameRequestBusyId === item.id} onClick={() => handleUsernameRequest(item.id, "approve")}>
                      {usernameRequestBusyId === item.id ? "Speichere..." : "Freigeben"}
                    </Button>
                    <Button variant="danger" disabled={usernameRequestBusyId === item.id} onClick={() => handleUsernameRequest(item.id, "reject")}>
                      Ablehnen
                    </Button>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </Card>
      ) : null}

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
                  onChange={(e) => setDraftRoles((prev) => ({ ...prev, [item.id]: e.target.value as UserRole }))}
                  disabled={busyId === item.id || !canEditItemRole(item)}
                >
                  {editableRoleOptionsFor(item.role).map((roleOption) => (
                    <option key={roleOption} value={roleOption}>{roleOption}</option>
                  ))}
                </select>
                <Button
                  variant="secondary"
                  disabled={busyId === item.id || !canEditItemRole(item) || (draftRoles[item.id] ?? item.role) === item.role}
                  onClick={() => updateRole(item.id, draftRoles[item.id] ?? item.role)}
                >
                  {busyId === item.id ? "Speichere..." : "Rolle speichern"}
                </Button>
              </div>
            ) : null}
            {item.isRoleImmutable ? <p className="qb-muted">Bootstrap-Admin: Rolle ist gesperrt.</p> : null}
            {canEditRoles ? (
              <Button variant="danger" disabled={busyId === item.id || item.id === myUserId} onClick={() => deleteUser(item.id)}>
                {busyId === item.id ? "Loesche..." : "User loeschen"}
              </Button>
            ) : null}
          </Card>
        ))}
      </div>
      <div className="qb-inline" style={{ justifyContent: "space-between" }}>
        <p className="qb-muted">Seite {currentPage} / {totalPages} ({visibleItems.length} User)</p>
        <div className="qb-inline">
          <Button variant="secondary" disabled={currentPage <= 1} onClick={() => setPage((prev) => Math.max(1, prev - 1))}>Zurueck</Button>
          <Button variant="secondary" disabled={currentPage >= totalPages} onClick={() => setPage((prev) => Math.min(totalPages, prev + 1))}>Weiter</Button>
        </div>
      </div>
    </section>
  );
}
