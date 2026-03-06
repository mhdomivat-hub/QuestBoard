import ProgressBar from "./ProgressBar";

type ProgressWithLegendProps = {
  delivered: number;
  collectedPending: number;
  remaining: number;
  max: number;
};

export default function ProgressWithLegend({
  delivered,
  collectedPending,
  remaining,
  max
}: ProgressWithLegendProps) {
  const safeDelivered = Math.max(delivered, 0);
  const safeCollected = Math.max(collectedPending, 0);
  const safeRemaining = Math.max(remaining, 0);
  const total = safeDelivered + safeCollected + safeRemaining;

  return (
    <>
      <ProgressBar value={safeDelivered} secondaryValue={safeCollected} max={max} />
      {total > 0 ? (
        <div className="qb-progress-legend">
          {safeDelivered > 0 ? (
            <span className="qb-progress-legend-item qb-progress-legend-delivered" style={{ flex: safeDelivered }}>
              Abgegeben {safeDelivered}
            </span>
          ) : null}
          {safeCollected > 0 ? (
            <span className="qb-progress-legend-item qb-progress-legend-collected" style={{ flex: safeCollected }}>
              Gesammelt {safeCollected}
            </span>
          ) : null}
          {safeRemaining > 0 ? (
            <span className="qb-progress-legend-item qb-progress-legend-open" style={{ flex: safeRemaining }}>
              Offen {safeRemaining}
            </span>
          ) : null}
        </div>
      ) : null}
    </>
  );
}
