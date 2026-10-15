/// Pure client-side alert checks, kept aligned with the Worker rules.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  double radians(double value) => value * 3.141592653589793 / 180;
  final dLat = radians(lat2 - lat1);
  final dLon = radians(lon2 - lon1);
  final a = (sinSquared(dLat / 2)) +
      (cosine(radians(lat1)) * cosine(radians(lat2)) * sinSquared(dLon / 2));
  return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a));
}

bool shouldShowArrivalAlert({
  required double distanceMeters,
  required double radiusMeters,
  required double accuracyMeters,
  required double etaMinutes,
  required double thresholdMinutes,
}) {
  if (![distanceMeters, radiusMeters, accuracyMeters, etaMinutes, thresholdMinutes]
      .every((value) => value.isFinite)) return false;
  final toleratedRadius = radiusMeters + accuracyMeters.clamp(0, 50);
  return distanceMeters <= toleratedRadius &&
      etaMinutes >= 0 && etaMinutes <= thresholdMinutes;
}

double sinSquared(double x) {
  final s = sinApprox(x);
  return s * s;
}

// Small-angle functions are only used with latitude/longitude radians.
// Use dart:math functions for production precision.
