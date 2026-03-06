"use client";

import { useLayoutEffect, useMemo, useRef, useState } from "react";
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
  const minGapPx = 10;
  const trackRef = useRef<HTMLDivElement | null>(null);
  const itemRefs = useRef<Record<string, HTMLSpanElement | null>>({});
  const [positions, setPositions] = useState<Record<string, number>>({});

  const segments = useMemo(() => {
    const result: Array<{ key: string; text: string; value: number; targetRatio: number; className: string }> = [];
    if (total <= 0) return result;

    let cursor = 0;
    const push = (
      key: string,
      text: string,
      value: number,
      className: string,
      ratioWithinSegment: number = 0.5
    ) => {
      if (value <= 0) return;
      const targetRatio = (cursor + value * ratioWithinSegment) / total;
      result.push({ key, text, value, targetRatio, className });
      cursor += value;
    };

    push("delivered", `Abgegeben ${safeDelivered}`, safeDelivered, "qb-progress-legend-delivered");
    push("collected", `Gesammelt ${safeCollected}`, safeCollected, "qb-progress-legend-collected");
    // Place "Offen" farther to the right inside the remaining segment for better visual separation.
    push("open", `Offen ${safeRemaining}`, safeRemaining, "qb-progress-legend-open", 0.82);
    return result;
  }, [safeDelivered, safeCollected, safeRemaining, total]);

  useLayoutEffect(() => {
    if (!trackRef.current || segments.length === 0) {
      setPositions({});
      return;
    }

    const compute = () => {
      const trackWidth = trackRef.current?.clientWidth ?? 0;
      if (trackWidth <= 0) return;

      const laidOut = segments.map((seg) => {
        const el = itemRefs.current[seg.key];
        const width = el?.offsetWidth ?? 0;
        const rawLeft = seg.targetRatio * trackWidth - width / 2;
        const clampedLeft = Math.max(0, Math.min(rawLeft, Math.max(trackWidth - width, 0)));
        return { ...seg, width, left: clampedLeft };
      });

      for (let i = 1; i < laidOut.length; i++) {
        const prev = laidOut[i - 1];
        const cur = laidOut[i];
        const minLeft = prev.left + prev.width + minGapPx;
        if (cur.left < minLeft) {
          cur.left = minLeft;
        }
      }

      const last = laidOut[laidOut.length - 1];
      const overflow = last.left + last.width - trackWidth;
      if (overflow > 0) {
        for (const item of laidOut) {
          item.left -= overflow;
        }
      }

      if (laidOut[0].left < 0) {
        laidOut[0].left = 0;
        for (let i = 1; i < laidOut.length; i++) {
          const prev = laidOut[i - 1];
          const cur = laidOut[i];
          const minLeft = prev.left + prev.width + minGapPx;
          cur.left = Math.max(cur.left, minLeft);
        }
      }

      const nextPositions: Record<string, number> = {};
      for (const item of laidOut) {
        nextPositions[item.key] = Math.max(0, item.left);
      }
      setPositions(nextPositions);
    };

    compute();
    window.addEventListener("resize", compute);
    return () => window.removeEventListener("resize", compute);
  }, [segments]);

  return (
    <>
      <ProgressBar value={safeDelivered} secondaryValue={safeCollected} max={max} />
      {total > 0 ? (
        <div className="qb-progress-legend-track" ref={trackRef}>
          {segments.map((seg) => (
            <span
              key={seg.key}
              ref={(el) => {
                itemRefs.current[seg.key] = el;
              }}
              className={`qb-progress-legend-item ${seg.className}`}
              style={{ left: positions[seg.key] != null ? `${positions[seg.key]}px` : "0px" }}
            >
              {seg.text}
            </span>
          ))}
        </div>
      ) : null}
    </>
  );
}
