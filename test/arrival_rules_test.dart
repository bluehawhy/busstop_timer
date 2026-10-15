import 'package:flutter_test/flutter_test.dart';
import 'package:busstop_timer/arrival_rules.dart';

void main() {
  group('arrival alert rules', () {
    test('uses a 30m radius with a capped GPS accuracy allowance', () {
      expect(shouldShowArrivalAlert(
        distanceMeters: 80, radiusMeters: 30, accuracyMeters: 50,
        etaMinutes: 5, thresholdMinutes: 5), isTrue);
      expect(shouldShowArrivalAlert(
        distanceMeters: 81, radiusMeters: 30, accuracyMeters: 50,
        etaMinutes: 5, thresholdMinutes: 5), isFalse);
    });

    test('rejects bus arrivals outside the five minute threshold', () {
      expect(shouldShowArrivalAlert(
        distanceMeters: 1, radiusMeters: 30, accuracyMeters: 0,
        etaMinutes: 5, thresholdMinutes: 5), isTrue);
      expect(shouldShowArrivalAlert(
        distanceMeters: 1, radiusMeters: 30, accuracyMeters: 0,
        etaMinutes: 5.1, thresholdMinutes: 5), isFalse);
    });

    test('rejects invalid values', () {
      expect(shouldShowArrivalAlert(
        distanceMeters: double.nan, radiusMeters: 30, accuracyMeters: 0,
        etaMinutes: 2, thresholdMinutes: 5), isFalse);
    });
  });
}
