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
          <footer className="qb-footer">
            <a className="qb-footer-link" href="/datenschutz">Datenschutz</a>
            <a className="qb-footer-link" href="/impressum">Impressum</a>
          </footer>
        </div>
      </body>
    </html>
  );
}
