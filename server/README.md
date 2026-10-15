# Cloudflare Worker + D1 API

This folder contains an initial backend implementation for bus stops, user subscriptions, device location evaluation, arrival lookup, and alert cooldowns.

## Setup

1. Install Node.js and run `npm install` from this directory.
2. Create a D1 database: `npx wrangler d1 create busstop-timer-db`.
3. Copy the returned database ID into `wrangler.toml`.
4. Apply the schema locally with `npm run db:local`; use `npm run db:remote` after reviewing the production target.
5. Set `BUS_ARRIVALS_URL` as a Worker variable to a provider adapter endpoint that accepts `?stopId=...` and returns `{ "arrivals": [{ "stopId": "...", "routeId": "...", "etaMinutes": 3.5, "updatedAt": "..." }] }`. Set `BUS_API_KEY` as a secret if required by that adapter.
6. Run `npm test`, `npm run dev`, then deploy with `npm run deploy`.
7. In the Flutter app, run `flutter pub get` after pulling this branch. Set `apiBaseUrl` and a stable per-install `userId` when constructing `BusTimerRuntime`; call `start()` only after the user turns alerts on. Call `stop()` when they turn alerts off. Never put a shared API or transit-provider secret in the app.

The Worker cannot query every Korean local transit API with one universal contract. The adapter must translate the selected city/provider response to the normalized schema above. Without it, arrivals report `providerStatus: not_configured`; no fake arrival is returned.

## API

- `GET /health`
- `GET /api/stops?lat=37.56&lon=126.97&radius=1000`
- `POST /api/stops`: `{id,name,latitude,longitude,providerStopId?}`
- `POST /api/subscriptions`: `{userId,stopId,routeId,routeName?,radiusMeters?,etaThresholdMinutes?,scheduleStart?,scheduleEnd?,weekdays?,timezone?}`
- `GET /api/subscriptions?userId=...`
- `DELETE /api/subscriptions/:id?userId=...`
- `GET /api/arrivals?stopId=...`
- `POST /api/evaluate`: `{userId,latitude,longitude,accuracyMeters,recordedAt?}`

Location is evaluated only from a fresh client fix and coordinates are not stored in D1. An ETA within five minutes generates one event when the device is within the stop radius (with GPS accuracy tolerance capped at 50m) and the subscription is inside its weekday/time window (default timezone: Asia/Seoul). Duplicate alert events are suppressed for ten minutes.

## Security and production requirements

All API routes except `/health` now fail closed unless `API_BEARER_TOKEN` is set. Use that only for local/private preview calls; a shared secret must never be embedded in a mobile/web client. The Flutter runtime's `previewBearerToken` exists for private development only. Before release, add per-user authentication (OIDC/Firebase Auth/Cloudflare Access-compatible identity), enforce ownership from verified token claims, rate limiting, provider-specific quotas, data retention/deletion jobs, and privacy disclosures. The current `userId` request fields are identifiers, not authentication. The Worker evaluates each submitted coordinate in memory; D1 stores no location history.

## App runtime and background limits

`lib/services/bus_timer_runtime.dart` requests user permission, streams GPS, calls the evaluate endpoint, and displays an immediate local notification when the API returns a matching arrival. Android uses a foreground location service notification; iOS enables background location updates. Web can show a browser notification while the page is active and permitted, but browsers do not provide reliable continuous GPS when the page is closed.

The runtime must be explicitly started and stopped by app UI; it is not silently activated at launch. OS force-stop, revoked permissions, battery optimization, poor GPS accuracy, network loss, and platform policy can interrupt tracking. Remote push delivery after the app process is gone is not implemented: APNs/FCM/Web Push credentials and per-user auth are still needed. This repository has no live transit provider configured.

## Tests

`npm test` checks backend distance, radius/accuracy tolerance, ETA bounds, Korean timezone schedules including overnight weekdays, and upstream response validation. `flutter test` covers client-side geofence/ETA rules. The workflow also runs `flutter analyze`.
