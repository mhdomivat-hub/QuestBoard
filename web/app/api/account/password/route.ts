import { cookies } from "next/headers";
import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";
const COOKIE_SECURE = (process.env.AUTH_COOKIE_SECURE || "false").toLowerCase() === "true";

export async function POST(req: Request) {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const payload = await req.json();
  const res = await fetch(`${API_BASE}/account/password`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  const text = await res.text();
  const out = new NextResponse(text, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });

  if (res.ok) {
    out.cookies.set(COOKIE_NAME, "", {
      httpOnly: true,
      sameSite: "lax",
      secure: COOKIE_SECURE,
      path: "/",
      maxAge: 0
    });
  }

  return out;
}
