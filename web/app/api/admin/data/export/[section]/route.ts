import { cookies } from "next/headers";
import { NextRequest, NextResponse } from "next/server";

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://api:8080";
const COOKIE_NAME = process.env.AUTH_COOKIE_NAME || "qb_token";

export async function GET(
  req: NextRequest,
  { params }: { params: { section: string } }
) {
  const token = cookies().get(COOKIE_NAME)?.value;
  if (!token) return NextResponse.json({ error: "Not authenticated" }, { status: 401 });

  const qs = req.nextUrl.searchParams.toString();
  const url = `${API_BASE}/admin/data/export/${encodeURIComponent(params.section)}${qs ? `?${qs}` : ""}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    cache: "no-store"
  });

  const body = await res.text();
  return new NextResponse(body, {
    status: res.status,
    headers: { "Content-Type": "application/json" }
  });
}

