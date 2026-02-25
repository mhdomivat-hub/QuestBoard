export default function ProgressBar({ value, max }: { value: number; max: number }) {
  const safeMax = Math.max(max, 1);
  const percent = Math.max(0, Math.min(100, Math.round((value / safeMax) * 100)));
  return (
    <div className="qb-progress" aria-label={`Progress ${percent}%`}>
      <div className="qb-progress-bar" style={{ width: `${percent}%` }} />
    </div>
  );
}
