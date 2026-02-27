export const STATUS_LABELS: Record<string, string> = {
  OPEN: "Offen",
  IN_PROGRESS: "Bearbeitung",
  DONE: "Fertig",
  ARCHIVED: "Archiviert",
  CLAIMED: "In Beschaffung",
  COLLECTED: "Gesammelt",
  DELIVERED: "Abgegeben",
  CANCELLED: "Abgebrochen",
  PENDING: "Ausstehend",
  APPROVED: "Freigegeben",
  COMPLETED: "Abgeschlossen",
  REJECTED: "Abgelehnt",
  member: "Mitglied",
  admin: "Admin",
  superAdmin: "SuperAdmin"
};

export function statusLabel(value: string): string {
  return STATUS_LABELS[value] ?? value;
}
