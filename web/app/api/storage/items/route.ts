import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { createHash } from "node:crypto";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";

export async function GET(req: Request) {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const res = await fetch(`${API_BASE}/storage/items`, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store"
  });

  const text = await res.text();
  const etag = `"${createHash("sha1").update(text).digest("hex")}"`;
  const requestETag = req.headers.get("if-none-match");
  if (requestETag === etag) {
    return new NextResponse(null, {
      status: 304,
      headers: {
        ETag: etag,
        "Cache-Control": "private, max-age=30, stale-while-revalidate=120",
        Vary: "Cookie, Accept-Encoding"
      }
    });
  }

  return new NextResponse(text, {
    status: res.status,
    headers: {
      "Content-Type": "application/json",
      ETag: etag,
      "Cache-Control": "private, max-age=30, stale-while-revalidate=120",
      Vary: "Cookie, Accept-Encoding"
    }
  });
}

export async function POST(req: Request) {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const payload = await req.json();
  const res = await fetch(`${API_BASE}/storage/items`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  const text = await res.text();
  return new NextResponse(text, { status: res.status, headers: { "Content-Type": "application/json" } });
}
