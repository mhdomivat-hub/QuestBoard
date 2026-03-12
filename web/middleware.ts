import { NextRequest, NextResponse } from "next/server";

const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";
const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";

const authPages = new Set([
  "/login",
  "/register",
  "/forgot-password",
  "/reset-password"
]);

const publicPages = new Set([
  ...authPages,
  "/datenschutz",
  "/impressum"
]);

const guestAllowedPaths = new Set([
  "/quests",
  "/datenschutz",
  "/impressum"
]);

function isGuestAllowedPath(pathname: string) {
  return guestAllowedPaths.has(pathname) || pathname.startsWith("/quests/");
}

export async function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Keep API behavior unchanged (401 on missing token) and do not intercept static assets.
  if (pathname.startsWith("/api") || pathname.startsWith("/_next") || pathname === "/favicon.ico") {
    return NextResponse.next();
  }

  const token = req.cookies.get(COOKIE_NAME)?.value;
  const isPublicPage = publicPages.has(pathname);

  if (!token && !isPublicPage) {
    const url = req.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  if (token && authPages.has(pathname)) {
    const url = req.nextUrl.clone();
    url.pathname = "/";
    url.searchParams.delete("next");
    return NextResponse.redirect(url);
  }

  if (token && pathname.startsWith("/admin")) {
    try {
      const res = await fetch(`${API_BASE}/me`, {
        headers: { Authorization: `Bearer ${token}` },
        cache: "no-store"
      });

      if (!res.ok) {
        const url = req.nextUrl.clone();
        url.pathname = "/login";
        url.searchParams.set("next", pathname);
        return NextResponse.redirect(url);
      }

      const me = (await res.json()) as { role?: string };
      if (me.role !== "admin" && me.role !== "superAdmin") {
        const url = req.nextUrl.clone();
        url.pathname = "/quests";
        return NextResponse.redirect(url);
      }
    } catch {
      const url = req.nextUrl.clone();
      url.pathname = "/quests";
      return NextResponse.redirect(url);
    }
  }

  if (token && !pathname.startsWith("/admin")) {
    try {
      const res = await fetch(`${API_BASE}/me`, {
        headers: { Authorization: `Bearer ${token}` },
        cache: "no-store"
      });

      if (!res.ok) {
        const url = req.nextUrl.clone();
        url.pathname = "/login";
        url.searchParams.set("next", pathname);
        return NextResponse.redirect(url);
      }

      const me = (await res.json()) as { role?: string };
      if (me.role === "guest" && !isGuestAllowedPath(pathname)) {
        const url = req.nextUrl.clone();
        url.pathname = "/quests";
        url.searchParams.delete("next");
        return NextResponse.redirect(url);
      }
    } catch {
      const url = req.nextUrl.clone();
      url.pathname = "/quests";
      return NextResponse.redirect(url);
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/:path*"]
};
