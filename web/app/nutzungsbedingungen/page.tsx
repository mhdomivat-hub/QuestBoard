import type { Metadata } from "next";
import Card from "../_components/ui/Card";

export const metadata: Metadata = {
  title: "Nutzungsbedingungen | QuestBoard",
};

export const dynamic = "force-dynamic";

export default function NutzungsbedingungenPage() {
  const legalName = (process.env.LEGAL_CONTACT_NAME ?? process.env.BOOTSTRAP_ADMIN_USERNAME ?? "Admin-Team").trim();
  const legalEmail = (process.env.LEGAL_CONTACT_EMAIL ?? "kontakt@example.invalid").trim();

  return (
    <main className="qb-main">
      <h1>Nutzungsbedingungen</h1>

      <Card>
        <h2 className="qb-card-title">Geltungsbereich</h2>
        <p className="qb-muted">
          QuestBoard und der dazugehoerige Discord-Bot sind ein privates, nicht-kommerzielles Angebot fuer den
          internen Gebrauch innerhalb der Community.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Zweck des Angebots</h2>
        <p className="qb-muted">
          Das System dient der Organisation von Quests, Rollen, Aktivitaetspruefungen und internen Community-Prozessen
          auf QuestBoard sowie den angebundenen Discord-Servern.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Nutzungsregeln</h2>
        <p className="qb-muted">
          Die Nutzung ist nur im Rahmen der Community-Regeln erlaubt. Missbrauch, Stoerung des Betriebs oder
          unberechtigte Nutzung koennen zum Entzug von Zugriffsrechten oder zum Ausschluss fuehren.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Discord-Bot und Aktivitaetsdaten</h2>
        <p className="qb-muted">
          Der Discord-Bot verarbeitet technisch erforderliche Ereignisse wie Nachrichten, Reaktionen und Voice- oder
          Stage-Aktivitaet, um Rollen fuer Inaktivitaetspruefungen zu setzen oder zu entfernen. Es werden keine
          weitergehenden Profildaten als fuer diese Funktion erforderlich dauerhaft gespeichert.
        </p>
      </Card>

      <Card>
        <h2 className="qb-card-title">Aenderungen und Kontakt</h2>
        <p className="qb-muted">
          Das Angebot kann jederzeit angepasst, eingeschraenkt oder eingestellt werden. Fragen dazu koennen an
          {` ${legalName} `}unter {legalEmail} gerichtet werden.
        </p>
      </Card>
    </main>
  );
}
