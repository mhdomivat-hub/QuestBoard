import type { Metadata } from "next";
import Card from "../_components/ui/Card";

export const metadata: Metadata = {
  title: "Datenschutz | QuestBoard"
};

export const dynamic = "force-dynamic";

export default function DatenschutzPage() {
  const legalName = (process.env.LEGAL_CONTACT_NAME ?? process.env.BOOTSTRAP_ADMIN_USERNAME ?? "Admin-Team").trim();
  const legalEmail = (process.env.LEGAL_CONTACT_EMAIL ?? "kontakt@example.invalid").trim();
  const legalCountry = (process.env.LEGAL_CONTACT_COUNTRY ?? "Deutschland").trim();

  return (
    <main className="qb-main">
      <h1>Datenschutz</h1>

      <Card>
        <h2 className="qb-card-title">Verantwortliche Stelle</h2>
        <p className="qb-muted">
          Verantwortlich fuer dieses interne Tool:
          <br />
          {legalName}
          <br />
          E-Mail: {legalEmail}
          <br />
          {legalCountry}
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Welche Daten verarbeitet werden</h2>
        <p className="qb-muted">
          Benutzerkonto-Daten (z. B. Username, Rolle), Quest- und Requirement-Daten, Contributions sowie
          sicherheitsrelevante Protokolle (z. B. Audit-Eintraege) zur Administration und Nachvollziehbarkeit.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Zweck und Rechtsgrundlage</h2>
        <p className="qb-muted">
          Verarbeitung erfolgt zur Bereitstellung und sicheren Nutzung des internen Systems. Rechtsgrundlage richtet
          sich nach eurem internen Einsatzkontext (z. B. berechtigtes Interesse, vertragliche/organisatorische
          Erforderlichkeit oder Beschaeftigtenkontext).
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Cookies und Session</h2>
        <p className="qb-muted">
          QuestBoard verwendet ein technisch notwendiges Session-Cookie zur Anmeldung. Ohne dieses Cookie kann die
          Anwendung nicht genutzt werden.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Speicherdauer und Rechte</h2>
        <p className="qb-muted">
          Daten werden nur so lange gespeichert, wie es fuer Betrieb, Sicherheit und interne Nachvollziehbarkeit
          erforderlich ist. Betroffene Personen haben die gesetzlichen Datenschutzrechte gemaess anwendbarem Recht.
        </p>
      </Card>
    </main>
  );
}
