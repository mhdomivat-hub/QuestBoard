"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import Button from "./ui/Button";

const hideOnPaths = ["/login", "/register", "/forgot-password", "/reset-password"];
type UserRole = "guest" | "member" | "admin" | "superAdmin";

export default function AppNav() {
  const pathname = usePathname();
  const [role, setRole] = useState<UserRole | null>(null);

  useEffect(() => {
    async function loadMe() {
      const res = await fetch("/api/me", { cache: "no-store" });
      if (!res.ok) return;
      const me = await res.json();
      setRole((me.role as UserRole | undefined) ?? null);
    }
    loadMe();
  }, [pathname]);

  if (!pathname || hideOnPaths.includes(pathname)) {
    return null;
  }

  async function logout() {
    await fetch("/api/logout", { method: "POST" }).catch(() => {
      // Ignore errors and redirect to login anyway.
    });
    window.location.href = "/login";
  }

  return (
    <nav className="qb-nav">
      <a className="qb-nav-link" href="/">Home</a>
      <a className="qb-nav-link" href="/quests">Quests</a>
      {role === "admin" || role === "superAdmin" ? (
        <a className="qb-nav-link" href="/admin/password-resets">Admin</a>
      ) : null}
      <Button type="button" variant="secondary" onClick={logout}>Logout</Button>
    </nav>
  );
}
