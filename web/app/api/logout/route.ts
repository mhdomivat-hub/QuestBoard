import { cookies } from "next/headers";
import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";
const COOKIE_SECURE = (process.env.AUTH_COOKIE_SECURE || "false").toLowerCase() === "true";

export async function POST() {
  const token = cookies().get(COOKIE_NAME)?.value;

  if (token) {
    await fetch(`${API_BASE}/auth/logout`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
      cache: "no-store"
    }).catch(() => {
      // Ignore upstream errors and still clear client cookie.
    });
  }

  const out = NextResponse.json({ ok: true });
  out.cookies.set(COOKIE_NAME, "", {
    httpOnly: true,
    sameSite: "lax",
    secure: COOKIE_SECURE,
    path: "/",
    maxAge: 0
  });
  return out;
}
