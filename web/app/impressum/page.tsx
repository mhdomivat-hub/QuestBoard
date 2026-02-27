import type { Metadata } from "next";
import Card from "../_components/ui/Card";

export const metadata: Metadata = {
  title: "Impressum | QuestBoard"
};

export const dynamic = "force-dynamic";

export default function ImpressumPage() {
  const legalName = (process.env.LEGAL_CONTACT_NAME ?? process.env.BOOTSTRAP_ADMIN_USERNAME ?? "Admin-Team").trim();
  const legalEmail = (process.env.LEGAL_CONTACT_EMAIL ?? "kontakt@example.invalid").trim();
  const legalCountry = (process.env.LEGAL_CONTACT_COUNTRY ?? "Deutschland").trim();

  return (
    <main className="qb-main">
      <h1>Impressum</h1>

      <Card>
        <h2 className="qb-card-title">Anbieter</h2>
        <p className="qb-muted">
          Privates, nicht-kommerzielles internes Tool einer losen Gruppe.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Kontakt</h2>
        <p className="qb-muted">
          Verantwortlich: {legalName}
          <br />
          E-Mail: {legalEmail}
          <br />
          Standort: {legalCountry}
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Hinweis</h2>
        <p className="qb-muted">
          Dieses Angebot richtet sich ausschliesslich an den internen Kreis der Gruppe.
        </p>
      </Card>
    </main>
  );
}
