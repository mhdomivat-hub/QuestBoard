"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import Button from "./ui/Button";

const hideOnPaths = ["/login", "/register", "/forgot-password", "/reset-password"];
type UserRole = "guest" | "member" | "admin" | "superAdmin";
const MOBILE_VERSION_STORAGE_KEY = "qb_mobile_version_enabled";

function applyMobileVersion(enabled: boolean) {
  if (typeof document === "undefined") return;
  document.documentElement.dataset.qbMobileVersion = enabled ? "on" : "off";
}

export default function AppNav() {
  const pathname = usePathname();
  const [role, setRole] = useState<UserRole | null>(null);
  const [mobileVersionEnabled, setMobileVersionEnabled] = useState(false);

  useEffect(() => {
    async function loadMe() {
      const res = await fetch("/api/me", { cache: "no-store" });
      if (!res.ok) return;
      const me = await res.json();
      setRole((me.role as UserRole | undefined) ?? null);
    }
    loadMe();
  }, [pathname]);

  useEffect(() => {
    if (typeof window === "undefined") return;

    const stored = window.localStorage.getItem(MOBILE_VERSION_STORAGE_KEY);
    const initialEnabled = stored === null ? window.innerWidth <= 768 : stored === "true";
    if (stored === null) {
      window.localStorage.setItem(MOBILE_VERSION_STORAGE_KEY, initialEnabled ? "true" : "false");
    }
    setMobileVersionEnabled(initialEnabled);
    applyMobileVersion(initialEnabled);
  }, []);

  if (!pathname || hideOnPaths.includes(pathname)) {
    return null;
  }

  async function logout() {
    await fetch("/api/logout", { method: "POST" }).catch(() => {
      // Ignore errors and redirect to login anyway.
    });
    window.location.href = "/login";
  }

  function toggleMobileVersion() {
    const nextValue = !mobileVersionEnabled;
    setMobileVersionEnabled(nextValue);
    if (typeof window !== "undefined") {
      window.localStorage.setItem(MOBILE_VERSION_STORAGE_KEY, nextValue ? "true" : "false");
    }
    applyMobileVersion(nextValue);
  }

  return (
    <nav className="qb-nav">
      <a className="qb-nav-link" href="/quests">Quests</a>
      {role !== "guest" ? <a className="qb-nav-link" href="/">Home</a> : null}
      {role !== "guest" ? <a className="qb-nav-link" href="/items">Items</a> : null}
      {role !== "guest" ? <a className="qb-nav-link" href="/loadouts">Loadouts</a> : null}
      {role !== "guest" ? <a className="qb-nav-link" href="/account">Account</a> : null}
      {role === "admin" || role === "superAdmin" ? (
        <a className="qb-nav-link" href="/admin/password-resets">Admin</a>
      ) : null}
      <div style={{ marginLeft: "auto" }}>
        <Button type="button" variant={mobileVersionEnabled ? "primary" : "secondary"} onClick={toggleMobileVersion}>
          MobileVersion
        </Button>
      </div>
      <Button type="button" variant="secondary" onClick={logout}>Logout</Button>
    </nav>
  );
}

