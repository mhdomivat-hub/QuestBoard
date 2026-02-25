import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";
const COOKIE_SECURE = (process.env.AUTH_COOKIE_SECURE || "false").toLowerCase() === "true";

export async function POST(req: Request) {
  const payload = await req.json();

  const res = await fetch(`${API_BASE}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  const text = await res.text();
  const out = new NextResponse(text, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });

  if (res.ok) {
    const body = JSON.parse(text);
    out.cookies.set(COOKIE_NAME, body.token, {
      httpOnly: true,
      sameSite: "lax",
      secure: COOKIE_SECURE,
      path: "/",
      maxAge: 60 * 60 * 24 * 7
    });
  }

  return out;
}
