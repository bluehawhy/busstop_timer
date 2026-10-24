import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bus_data_service.dart';
import 'services/journey_service.dart';

class LiveBusPage extends ConsumerStatefulWidget {
  const LiveBusPage({super.key});
  @override
  ConsumerState<LiveBusPage> createState() => _LiveBusPageState();
}

class _LiveBusPageState extends ConsumerState<LiveBusPage> {
  final _token = TextEditingController();
  final _query = TextEditingController();
  JourneyService? _api;
  List<dynamic> _cities = [], _stops = [], _routes = [], _saved = [], _arrivals = [];
  int? _city;
  Map<String, dynamic>? _stop;
  String? _error;
  bool _busy = false;
  int _page = 1, _total = 0;

  @override
  void dispose() {
    _token.dispose(); _query.dispose(); _api?.dispose(); super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await action(); } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  String _searchPath(int page) {
    final city = _cities[_city!];
    final query = _query.text.trim();
    final params = <String, String>{'provider': city['provider'] as String, 'page': '$page',
      if (city['cityCode'] != null) 'cityCode': '${city['cityCode']}',
      if (RegExp(r'^\d+$').hasMatch(query)) 'arsNo': query else 'q': query};
    return 'bus/stops/search?${Uri(queryParameters: params).query}';
  }

  Future<void> _search(int page) => _run(() async {
    final result = await _api!.request(_searchPath(page));
    if (!mounted) return;
    setState(() {
      _stops = result['stops'] as List<dynamic>; _page = page;
      _total = result['totalCount'] as int? ?? 0; _stop = null; _routes = [];
    });
  });

  Future<void> _refresh() async {
    final saved = await _api!.request('bus/subscriptions');
    final rows = saved['subscriptions'] as List<dynamic>;
    final arrivals = <dynamic>[];
    final home = <BusArrivalInfo>[];
    for (final stopId in rows.map((s) => s['stopId']).toSet()) {
      final result = await _api!.request('bus/arrivals?${Uri(queryParameters: {'stopId': '$stopId'}).query}');
      for (final sub in rows.where((s) => s['stopId'] == stopId)) {
        final live = (result['arrivals'] as List<dynamic>).where((a) => a['routeId'] == sub['routeId']).toList();
        arrivals.addAll(live.map((a) => {...a, 'stopName': sub['stopName']}));
        String label(dynamic a) => a['etaMinutes'] == null ? '도착정보 없음' : '${a['etaMinutes']}분${a['basis'] == 'historical_estimate' ? ' (이력 추정)' : ''}';
        home.add(BusArrivalInfo(recordId: '${sub['id']}', station: '${sub['stopName']}', busNum: '${sub['routeName']}',
          remain: live.isEmpty ? '도착정보 없음' : label(live.first), nextBus: live.length > 1 ? label(live[1]) : null));
      }
    }
    if (!mounted) return;
    setState(() { _saved = rows; _arrivals = arrivals; });
    ref.read(busListProvider.notifier).replaceBuses(home);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 버스 조회')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('기기 토큰으로 연결하면 도시별 정류장 검색과 내 버스 저장을 이용할 수 있어요.'),
        TextField(controller: _token, obscureText: true, decoration: const InputDecoration(labelText: '개인 기기 토큰')),
        FilledButton(onPressed: _busy ? null : () => _run(() async {
          if (_token.text.trim().isEmpty) throw Exception('기기 토큰을 입력해주세요.');
          _api?.dispose(); _api = JourneyService(token: _token.text.trim());
          if (mounted) setState(() { _cities = []; _city = null; _stops = []; _routes = []; _saved = []; _arrivals = []; _stop = null; });
          final result = await _api!.request('bus/cities');
          if (!mounted) return;
          setState(() { _cities = result['cities'] as List<dynamic>; _city = _cities.isEmpty ? null : 0; });
          await _refresh();
        }), child: const Text('연결')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) SelectableText(_error!, style: const TextStyle(color: Colors.red)),
        if (_api != null && !_busy && _cities.isEmpty) const Text('조회 가능한 도시가 없습니다. 서버의 API 키와 활용 승인을 확인해주세요.'),
        if (_cities.isNotEmpty) ...[
          DropdownButton<int>(value: _city, isExpanded: true, items: [
            for (var i = 0; i < _cities.length; i++) DropdownMenuItem(value: i, child: Text('${_cities[i]['name']} (${_cities[i]['provider']})')),
          ], onChanged: _busy ? null : (value) => setState(() { _city = value; _stops = []; _routes = []; _stop = null; _total = 0; _page = 1; })),
          TextField(controller: _query, enabled: !_busy, decoration: const InputDecoration(labelText: '정류장 이름 또는 번호'), onSubmitted: (_) { if (!_busy) _search(1); }),
          FilledButton(onPressed: _busy ? null : () => _search(1), child: const Text('정류장 검색')),
          for (final s in _stops) ListTile(title: Text('${s['name']}'), subtitle: Text('${s['arsNo'] ?? s['providerStopId']}'),
            selected: _stop?['id'] == s['id'], onTap: _busy ? null : () => _run(() async {
              final result = await _api!.request('bus/routes?${Uri(queryParameters: {'stopId': '${s['id']}'}).query}');
              if (mounted) setState(() { _stop = Map<String,dynamic>.from(s as Map); _routes = result['routes'] as List<dynamic>; });
              if (!['ok','cached'].contains(result['providerStatus'])) throw Exception('도착정보 조회 실패: ${result['providerStatus']}');
            })),
          Row(children: [
            TextButton(onPressed: _busy || _page <= 1 ? null : () => _search(_page - 1), child: const Text('이전')),
            Text('$_page 페이지'),
            TextButton(onPressed: _busy || _page * 100 >= _total ? null : () => _search(_page + 1), child: const Text('다음')),
          ]),
          if (_stop != null) Text('${_stop!['name']} · 조회된 노선'),
          for (final r in _routes) ListTile(title: Text('${r['routeName']}'), trailing: TextButton(onPressed: _busy ? null : () => _run(() async {
            await _api!.request('bus/subscriptions', body: {'stopId': _stop!['id'], 'routeId': r['routeId']});
            await _refresh();
          }), child: const Text('저장'))),
        ],
        if (_api != null) ...[
          const Divider(), const Text('내 버스'),
          const Text('도착정보는 새로고침 시 갱신됩니다. 전체 노선이 아닌 현재 공급자가 반환한 노선을 표시합니다.'),
          TextButton(onPressed: _busy ? null : () => _run(_refresh), child: const Text('도착정보 새로고침')),
          for (final s in _saved) ListTile(title: Text('${s['stopName']} · ${s['routeName']}'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: _busy ? null : () => _run(() async {
              await _api!.request('bus/subscriptions/${s['id']}', method: 'DELETE'); await _refresh();
            }))),
          for (final a in _arrivals) ListTile(title: Text('${a['stopName']} · ${a['routeName']}'), subtitle: Text(
            a['etaMinutes'] == null ? '도착정보 없음 · ${a['fallbackReason'] ?? a['reason'] ?? ''}' :
            '${a['etaMinutes']}분 · ${a['basis'] == 'realtime' ? '실시간' : '이력 추정'}')),
        ],
      ]),
    );
  }
}
