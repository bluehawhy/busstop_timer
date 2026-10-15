export function haversineMeters(lat1, lon1, lat2, lon2) {
  const radians = (degrees) => degrees * Math.PI / 180;
  const dLat = radians(lat2 - lat1);
  const dLon = radians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(lat1)) * Math.cos(radians(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function isWithinSchedule(date, start, end, weekdays, timeZone = 'Asia/Seoul') {
  let parts;
  try {
    parts = new Intl.DateTimeFormat('en-US', {
      timeZone, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
    }).formatToParts(date).reduce((values, part) => ({ ...values, [part.type]: part.value }), {});
  } catch { return false; }
  const day = ({ Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 })[parts.weekday];
  const now = Number(parts.hour) * 60 + Number(parts.minute);
  const [sh, sm] = start.split(':').map(Number);
  const [eh, em] = end.split(':').map(Number);
  const from = sh * 60 + sm;
  const to = eh * 60 + em;
  if (from <= to) return weekdays.includes(day) && now >= from && now <= to;
  const previousDay = day === 1 ? 7 : day - 1;
  return (weekdays.includes(day) && now >= from) ||
    (weekdays.includes(previousDay) && now <= to);
}

export function shouldAlert({ distanceMeters, radiusMeters, accuracyMeters, etaMinutes, thresholdMinutes }) {
  if (!Number.isFinite(distanceMeters) || !Number.isFinite(etaMinutes)) return false;
  // GPS accuracy is a capped tolerance to reduce missed alerts, not a guarantee of exact location.
  const toleratedRadius = radiusMeters + Math.min(Math.max(accuracyMeters || 0, 0), 50);
  return distanceMeters <= toleratedRadius && etaMinutes >= 0 && etaMinutes <= thresholdMinutes;
}

export function normalizeArrivals(payload) {
  const rows = Array.isArray(payload) ? payload : payload?.arrivals;
  if (!Array.isArray(rows)) throw new Error('BUS_PROVIDER_INVALID_RESPONSE');
  return rows.map((row) => {
    const eta = Number(row.etaMinutes);
    if (!row.stopId || !row.routeId || !Number.isFinite(eta) || eta < 0) return null;
    return { stopId: String(row.stopId), routeId: String(row.routeId), etaMinutes: eta,
      updatedAt: row.updatedAt ?? null };
  }).filter(Boolean);
}
