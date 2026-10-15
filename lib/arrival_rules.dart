import 'dart:math' as math;

/// Pure client-side geofence and ETA checks, aligned with the Worker rules.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  double radians(double value) => value * math.pi / 180;
  final dLat = radians(lat2 - lat1);
  final dLon = radians(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(radians(lat1)) * math.cos(radians(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
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
  final toleratedRadius = radiusMeters + accuracyMeters.clamp(0, 50).toDouble();
  return distanceMeters <= toleratedRadius &&
      etaMinutes >= 0 && etaMinutes <= thresholdMinutes;
}
