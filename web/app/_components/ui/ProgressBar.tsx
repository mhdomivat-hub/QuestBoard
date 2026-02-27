type ProgressBarProps = {
  value: number;
  max: number;
  secondaryValue?: number;
};

export default function ProgressBar({ value, max, secondaryValue = 0 }: ProgressBarProps) {
  const safeMax = Math.max(max, 1);
  const primary = Math.max(0, Math.min(value, safeMax));
  const secondary = Math.max(0, Math.min(secondaryValue, safeMax - primary));
  const primaryPercent = Math.max(0, Math.min(100, Math.round((primary / safeMax) * 100)));
  const secondaryPercent = Math.max(0, Math.min(100, Math.round((secondary / safeMax) * 100)));
  const totalPercent = Math.max(0, Math.min(100, primaryPercent + secondaryPercent));

  return (
    <div className="qb-progress" aria-label={`Progress ${totalPercent}%`}>
      <div className="qb-progress-segment qb-progress-bar" style={{ width: `${primaryPercent}%` }} />
      <div className="qb-progress-segment qb-progress-bar-secondary" style={{ width: `${secondaryPercent}%` }} />
    </div>
  );
}
