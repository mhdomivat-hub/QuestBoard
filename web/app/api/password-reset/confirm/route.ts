import { NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";

export async function POST(req: Request) {
  const payload = await req.json();

  const res = await fetch(`${API_BASE}/auth/password-reset/confirm`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  const text = await res.text().catch(() => "");
  return new NextResponse(text, { status: res.status });
}
