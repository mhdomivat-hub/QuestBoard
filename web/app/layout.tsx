import type { Metadata } from "next";
import React from "react";
import AppNav from "./_components/AppNav";
import "./globals.css";

export const metadata: Metadata = {
  title: "QuestBoard",
  description: "Org-internes Quest Board"
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="de">
      <body>
        <div className="qb-shell">
        <AppNav />
        {children}
        </div>
      </body>
    </html>
  );
}
