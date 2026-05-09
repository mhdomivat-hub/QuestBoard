import { statusLabel } from "./statusLabels";

type StatusValue =
  | "OPEN"
  | "IN_PROGRESS"
  | "DONE"
  | "ARCHIVED"
  | "PENDING"
  | "APPROVED"
  | "PRIORITAET"
  | "COMPLETED"
  | "REJECTED"
  | "CLAIMED"
  | "COLLECTED"
  | "DELIVERED"
  | "CANCELLED";

export default function Badge({ label }: { label: StatusValue | string }) {
  const highlight = ["DONE", "DELIVERED", "APPROVED", "COMPLETED", "PENDING", "PRIORITAET"].includes(label);
  return <span className={`qb-badge ${highlight ? "qb-badge-highlight" : ""}`.trim()}>{statusLabel(label)}</span>;
}
