import React from "react";

export default function Card({ className = "", children }: { className?: string; children: React.ReactNode }) {
  return <section className={`qb-card ${className}`.trim()}>{children}</section>;
}
