import test from 'node:test';
import assert from 'node:assert/strict';
import { haversineMeters, isWithinSchedule, normalizeArrivals, shouldAlert } from '../src/arrival.js';

test('distance uses meters and handles nearby coordinates', () => {
  assert.ok(haversineMeters(37.5665, 126.978, 37.5665, 126.9781) > 8);
  assert.ok(haversineMeters(37.5665, 126.978, 37.5665, 126.9781) < 10);
});

test('GPS accuracy is capped and radius boundary is inclusive', () => {
  assert.equal(shouldAlert({ distanceMeters: 80, radiusMeters: 30, accuracyMeters: 50, etaMinutes: 5, thresholdMinutes: 5 }), true);
  assert.equal(shouldAlert({ distanceMeters: 81, radiusMeters: 30, accuracyMeters: 50, etaMinutes: 5, thresholdMinutes: 5 }), false);
});

test('ETA must be non-negative and within threshold', () => {
  const base = { distanceMeters: 1, radiusMeters: 30, accuracyMeters: 0, thresholdMinutes: 5 };
  assert.equal(shouldAlert({ ...base, etaMinutes: 5 }), true);
  assert.equal(shouldAlert({ ...base, etaMinutes: 5.1 }), false);
  assert.equal(shouldAlert({ ...base, etaMinutes: -1 }), false);
});

test('schedule handles weekdays and overnight windows', () => {
  assert.equal(isWithinSchedule(new Date('2026-10-19T23:30:00'), '22:00', '06:00', [1]), true);
  assert.equal(isWithinSchedule(new Date('2026-10-20T05:30:00'), '22:00', '06:00', [1]), true);
  assert.equal(isWithinSchedule(new Date('2026-10-20T12:00:00'), '22:00', '06:00', [2]), false);
});

test('arrival provider payload is validated', () => {
  assert.deepEqual(normalizeArrivals({ arrivals: [{ stopId: 's1', routeId: '100', etaMinutes: 4 }] }),
    [{ stopId: 's1', routeId: '100', etaMinutes: 4, updatedAt: null }]);
  assert.throws(() => normalizeArrivals({ items: [] }), /INVALID_RESPONSE/);
});
