import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class JourneyService {
  JourneyService({required this.token, String? baseUrl})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('BUS_API_URL',
          defaultValue: 'https://bustimer.bluewaikiki.top')).replaceFirst(RegExp(r'/+$'), '');
  static final Map<String, Future<String>> _sessions = {};
  final String token;
  final String baseUrl;
  final http.Client _client = http.Client();

  static Future<String> _load(JourneyService api) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'bus_timer_guest:${api.baseUrl}';
    final saved = prefs.getString(key);
    if (saved != null && saved.isNotEmpty) return saved;
    final data = await api.request('auth/guest', body: {});
    final token = data['token'] as String;
    if (!await prefs.setString(key, token)) throw Exception('연결 정보를 저장하지 못했습니다.');
    return token;
  }

  static Future<JourneyService> connect({String? baseUrl}) async {
    final bootstrap = JourneyService(token: '', baseUrl: baseUrl);
    final base = bootstrap.baseUrl;
    JourneyService? api;
    try {
      final token = await (_sessions[base] ??= _load(bootstrap));
      api = JourneyService(token: token, baseUrl: base);
      try { await api.request('auth/status'); }
      on BusApiException catch (error) {
        if (error.status != 401) rethrow;
        api.dispose();
        await _forget(base);
        final fresh = await (_sessions[base] ??= _load(bootstrap));
        api = JourneyService(token: fresh, baseUrl: base);
      }
      return api;
    } catch (_) { api?.dispose(); _sessions.remove(base); rethrow; }
    finally { bootstrap.dispose(); }
  }

  static Future<void> _forget(String base) async {
    _sessions.remove(base);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bus_timer_guest:$base');
  }

  Future<void> verifyEmail(String email, String code, String challengeId) async {
    final data = await request('auth/email-otp/verify', body: {'email': email, 'code': code, 'challengeId': challengeId});
    final updated = data['token'] as String;
    _sessions[baseUrl] = Future.value(updated);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString('bus_timer_guest:$baseUrl', updated)) throw Exception('로그인은 완료됐지만 연결 정보를 저장하지 못했습니다.');
  }

  Future<void> logout() async {
    try { await request('auth/logout', body: {}); }
    on BusApiException catch (error) { if (error.status != 401) rethrow; }
    await _forget(baseUrl);
  }

  Future<Map<String, dynamic>> request(String path, {Map<String, dynamic>? body, String method = 'GET'}) async {
    final active = path == 'auth/guest' ? '' : await (_sessions[baseUrl] ?? Future.value(token));
    final headers = {if (active.isNotEmpty) 'authorization': 'Bearer $active', 'content-type': 'application/json'};
    final uri = Uri.parse('$baseUrl/api/$path');
    final response = await (method == 'DELETE' ? _client.delete(uri, headers: headers)
        : body == null ? _client.get(uri, headers: headers)
        : _client.post(uri, headers: headers, body: jsonEncode(body))).timeout(const Duration(seconds: 35));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) throw BusApiException(response.statusCode, data['error'] as String? ?? 'REQUEST_FAILED');
    return data;
  }
  void dispose() => _client.close();
}

class BusApiException implements Exception {
  BusApiException(this.status, this.code);
  final int status;
  final String code;
  @override
  String toString() => switch (code) {
    'INVALID_EMAIL' => '이메일 주소를 확인해주세요.',
    'INVALID_OR_EXPIRED_OTP' => '인증번호가 올바르지 않거나 만료되었습니다.',
    'AUTH_RATE_LIMITED' => '요청이 많습니다. 잠시 후 다시 시도해주세요.',
    'AUTH_MAIL_NOT_CONFIGURED' || 'AUTH_NOT_CONFIGURED' => '서버의 이메일 인증 설정이 필요합니다.',
    'AUTH_MAIL_UNAVAILABLE' => '인증 메일을 보내지 못했습니다. 잠시 후 다시 시도해주세요.',
    'UNAUTHORIZED' => '로그인이 만료되었습니다. 화면을 다시 열어 이메일 인증을 진행해주세요.',
    'AUTH_MODE_CHANGED' => '인증 방식이 바뀌었습니다. 화면을 다시 열어주세요.',
    _ => '요청 실패: $code',
  };
}
