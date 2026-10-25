import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class JourneyService {
  JourneyService({required this.token, String? baseUrl})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('BUS_API_URL',
          defaultValue: 'https://bustimer.bluewaikiki.top')).replaceFirst(RegExp(r'/+$'), '');
  // Share initialization across pages so concurrent opens keep one guest identity.
  static final Map<String, Future<String>> _guestSessions = {};

  static Future<JourneyService> connect({String? baseUrl}) async {
    final api = JourneyService(token: '', baseUrl: baseUrl);
    final key = api.baseUrl;
    try {
      final token = await (_guestSessions[key] ??= _loadGuest(api));
      return JourneyService(token: token, baseUrl: key);
    } catch (_) {
      _guestSessions.remove(key);
      rethrow;
    } finally {
      api.dispose();
    }
  }

  static Future<String> _loadGuest(JourneyService api) async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'bus_timer_guest:${api.baseUrl}';
    final saved = preferences.getString(key);
    if (saved != null && saved.isNotEmpty) return saved;
    final result = await api.request('auth/guest', body: {});
    final token = result['token'] as String;
    if (token.isEmpty || !await preferences.setString(key, token)) {
      throw Exception('연결 정보를 저장하지 못했습니다. 다시 시도해주세요.');
    }
    return token;
  }

  final String token;
  final String baseUrl;
  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> request(String path, {Map<String, dynamic>? body, String method = 'GET'}) async {
    final uri = Uri.parse('$baseUrl/api/$path');
    final headers = {if (token.isNotEmpty) 'authorization': 'Bearer $token', 'content-type': 'application/json'};
    final response = await (method == 'DELETE'
        ? _client.delete(uri, headers: headers)
        : body == null ? _client.get(uri, headers: headers)
        : _client.post(uri, headers: headers, body: jsonEncode(body)))
        .timeout(const Duration(seconds: 20));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) throw Exception(data['error'] ?? '요청 실패');
    return data;
  }

  void dispose() => _client.close();
}
