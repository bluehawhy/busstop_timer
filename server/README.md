# Cloudflare Worker + D1 API

This folder contains an initial backend implementation for bus stops, user subscriptions, device location evaluation, arrival lookup, and alert cooldowns.

## Setup

1. Install Node.js and run `npm install` from this directory.
2. Create a D1 database: `npx wrangler d1 create busstop-timer-db`.
3. Copy the returned database ID into `wrangler.toml`.
4. Apply the schema locally with `npm run db:local`; use `npm run db:remote` after reviewing the production target.
5. Set `BUS_ARRIVALS_URL` as a Worker variable to a provider adapter endpoint that accepts `?stopId=...` and returns `{ "arrivals": [{ "stopId": "...", "routeId": "...", "etaMinutes": 3.5, "updatedAt": "..." }] }`. Set `BUS_API_KEY` as a secret if required by that adapter.
6. Run `npm test`, `npm run dev`, then deploy with `npm run deploy`.

The Worker cannot query every Korean local transit API with one universal contract. The adapter must translate the selected city/provider response to the normalized schema above. Without it, arrivals report `providerStatus: not_configured`; no fake arrival is returned.

## API

- `GET /health`
- `GET /api/stops?lat=37.56&lon=126.97&radius=1000`
- `POST /api/stops`: `{id,name,latitude,longitude,providerStopId?}`
- `POST /api/subscriptions`: `{userId,stopId,routeId,routeName?,radiusMeters?,etaThresholdMinutes?,scheduleStart?,scheduleEnd?,weekdays?}`
- `GET /api/subscriptions?userId=...`
- `DELETE /api/subscriptions/:id?userId=...`
- `GET /api/arrivals?stopId=...`
- `POST /api/evaluate`: `{userId,latitude,longitude,accuracyMeters,recordedAt?}`

Location is evaluated only from a fresh client fix. An ETA within five minutes generates one event when the device is within the stop radius (with GPS accuracy tolerance capped at 50m) and the subscription is inside its weekday/time window. Duplicate alert events are suppressed for ten minutes.

## Security and production requirements

This scaffold is not safe to expose as a public production API yet. The optional `API_BEARER_TOKEN` protects preview deployments, but a shared secret must never be embedded in a mobile/web client. Before release, add per-user authentication (OIDC/Firebase Auth/Cloudflare Access-compatible identity), enforce ownership from verified token claims, rate limiting, provider-specific quotas, data retention/deletion jobs, and privacy disclosures. The current `userId` request fields are identifiers, not authentication.

## Background alerts

D1 stores subscriptions and the Worker evaluates them, but it cannot wake an app or obtain fresh GPS while the OS has suspended it. Reliable closed-app alerts require a platform-specific background location/geofence implementation and push delivery (APNs/FCM/Web Push) with user permission and credentials. Those credentials and the actual transit provider are deployment inputs; this backend does not claim those integrations are configured.
