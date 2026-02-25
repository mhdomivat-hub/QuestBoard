import { cookies } from "next/headers";
import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";

export async function GET() {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const res = await fetch(`${API_BASE}/admin/invites`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store"
  });
  const body = await res.text();
  return new NextResponse(body, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });
}

export async function POST(req: Request) {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const payload = await req.json();
  const res = await fetch(`${API_BASE}/admin/invites`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
  const body = await res.text();
  return new NextResponse(body, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });
}

