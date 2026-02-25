import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";

export async function POST(req: Request) {
  const payload = await req.json();

  const res = await fetch(`${API_BASE}/auth/register-by-invite`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  const body = await res.text();
  return new NextResponse(body, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });
}

