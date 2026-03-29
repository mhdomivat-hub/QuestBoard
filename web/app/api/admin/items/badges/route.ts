import { cookies } from "next/headers";
import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";

async function forward(method: "POST" | "PATCH" | "DELETE", req: Request) {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const payload = await req.json();
  const res = await fetch(`${API_BASE}/admin/items/badges`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

  const text = await res.text();
  return new NextResponse(text, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });
}

export async function POST(req: Request) {
  return forward("POST", req);
}

export async function PATCH(req: Request) {
  return forward("PATCH", req);
}

export async function DELETE(req: Request) {
  return forward("DELETE", req);
}
