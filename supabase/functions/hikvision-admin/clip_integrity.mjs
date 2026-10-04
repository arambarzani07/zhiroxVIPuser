// A repeated file is suspicious only when its requested windows do not overlap.
// This is a warning about file identity, not proof of the footage's clock time.
export function duplicateWindow(a, b) {
  if (!a.content_sha256 || a.content_sha256 !== b.content_sha256 ||
      a.market_id !== b.market_id || a.channel_id !== b.channel_id ||
      a.id === b.id || a.status !== 'ready' || b.status !== 'ready') return false;
  const times = [a.clip_start_at, a.clip_end_at, b.clip_start_at, b.clip_end_at].map(Date.parse);
  const [as, ae, bs, be] = times;
  return times.every(Number.isFinite) && as < ae && bs < be && (ae <= bs || be <= as);
}

export function summarizeClips(rows) {
  const flagged = new Set();
  for (let i = 0; i < rows.length; i++) {
    for (let j = i + 1; j < rows.length; j++) {
      if (duplicateWindow(rows[i], rows[j])) {
        flagged.add(rows[i].id);
        flagged.add(rows[j].id);
      }
    }
  }
  const latest = rows[0]; // Caller orders by captured_at DESC.
  return {
    sampled_clips: rows.length,
    suspicious_clips: flagged.size,
    latest_clip_build: latest?.playback_metadata?.gateway_build ?? null,
    latest_clip_captured_at: latest?.captured_at ?? null,
  };
}
