import 'dart:convert';
import 'package:http/http.dart' as http;

class JourneyService {
  JourneyService({required this.token, String? baseUrl})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('BUS_API_URL',
          defaultValue: 'https://bustimer.bluewaikiki.top')).replaceFirst(RegExp(r'/+$'), '');
  final String token;
  final String baseUrl;
  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> request(String path, {Map<String, dynamic>? body, String method = 'GET'}) async {
    final uri = Uri.parse('$baseUrl/api/$path');
    final headers = {'authorization': 'Bearer $token', 'content-type': 'application/json'};
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
