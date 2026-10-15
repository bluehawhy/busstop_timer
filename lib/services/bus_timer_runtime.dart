import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Connect this runtime after the user explicitly enables arrival alerts.
class BusTimerRuntime {
  BusTimerRuntime({
    required this.apiBaseUrl,
    required this.userId,
    http.Client? client,
    FlutterLocalNotificationsPlugin? notifications,
  })  : _client = client ?? http.Client(),
        _notifications = notifications ?? FlutterLocalNotificationsPlugin();

  final String apiBaseUrl;
  final String userId;
  final http.Client _client;
  final FlutterLocalNotificationsPlugin _notifications;
  StreamSubscription<Position>? _positionSubscription;
  bool _started = false;

  bool get isStarted => _started;

  Future<void> initializeNotifications() async {
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        web: WebInitializationSettings(
          defaultIcon: 'icons/Icon-192.png',
        ),
      ),
    );
  }

  /// Call from a user gesture (for web permission prompt and OS permission UX).
  Future<bool> start() async {
    if (_started) return true;
    await initializeNotifications();
    if (kIsWeb) {
      final web = _notifications.resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin>();
      if (web == null) return false;
      final permission = await web.requestNotificationsPermission();
      if (permission != WebNotificationPermission.granted) return false;
    } else {
      final notificationPermission = await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      if (notificationPermission == false) return false;
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever ||
        permission == LocationPermission.unableToDetermine) {
      return false;
    }

    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: '버스 도착 알림 추적 중',
              notificationText: '등록한 정류장과 버스 도착 정보를 확인합니다.',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : defaultTargetPlatform == TargetPlatform.iOS
            ? AppleSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 10,
                pauseLocationUpdatesAutomatically: false,
                allowBackgroundLocationUpdates: true,
                showBackgroundLocationIndicator: true,
              )
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 10,
              );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_evaluatePosition, onError: (Object error) {
      debugPrint('Bus Timer location stream error: $error');
    });
    _started = true;
    return true;
  }

  Future<void> _evaluatePosition(Position position) async {
    if (position.accuracy > 100) return;
    final uri = Uri.parse('${apiBaseUrl.replaceFirst(RegExp(r'/+$'), '')}/api/evaluate');
    try {
      final response = await _client.post(uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracyMeters': position.accuracy,
          'recordedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final alerts = (data['alerts'] as List<dynamic>? ?? const []);
      for (final value in alerts) {
        final alert = value as Map<String, dynamic>;
        final subscriptionId = alert['subscriptionId'] as String? ?? '';
        final route = alert['routeName'] as String? ?? alert['routeId'] as String? ?? '등록 버스';
        final stop = alert['stopName'] as String? ?? '등록 정류장';
        final eta = (alert['etaMinutes'] as num?)?.toStringAsFixed(0) ?? '5';
        await _notifications.show(
          id: subscriptionId.hashCode & 0x7fffffff,
          title: '$route 버스 도착 알림',
          body: '$stop · 약 $eta분 후 도착 예정입니다.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'bus_arrival_alerts',
              '버스 도착 알림',
              channelDescription: '등록한 버스의 도착 예정 알림',
              importance: Importance.max,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
            web: WebNotificationDetails(requireInteraction: true),
          ),
          payload: subscriptionId,
        );
      }
    } catch (error) {
      debugPrint('Bus Timer alert evaluation failed: $error');
    }
  }

  Future<void> stop() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _started = false;
  }

  void dispose() {
    unawaited(stop());
    _client.close();
  }
}
