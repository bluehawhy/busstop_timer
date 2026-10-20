import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/journey_service.dart';

class JourneyHomePage extends StatefulWidget {
  const JourneyHomePage({super.key});
  @override
  State<JourneyHomePage> createState() => _JourneyHomePageState();
}

class _JourneyHomePageState extends State<JourneyHomePage> {
  final _token = TextEditingController();
  final _base = TextEditingController(text: const String.fromEnvironment('BUS_API_URL', defaultValue: 'https://bustimer.bluewaikiki.top'));
  final _notifications = FlutterLocalNotificationsPlugin();
  JourneyService? _api;
  List<dynamic> _stops = [], _comparisons = [], _saved = [];
  String? _origin, _destination, _error;
  DateTime _departure = DateTime.now();
  int _transfers = 2, _tab = 0;
  bool _busy = false, _polling = false, _notify = false, _departNow = true;
  Map<String, dynamic>? _session;
  Timer? _timer;
  final Set<String> _shown = {};

  @override
  void dispose() {
    _timer?.cancel(); _api?.dispose(); _token.dispose(); _base.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await action(); } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _connect() => _run(() async {
    final uri = Uri.tryParse(_base.text.trim());
    if (uri == null || !uri.hasAuthority || !['http','https'].contains(uri.scheme) || _token.text.trim().isEmpty) {
      throw Exception('서버 주소와 기기 토큰을 입력해주세요.');
    }
    _api?.dispose(); _api = JourneyService(token: _token.text.trim(), baseUrl: _base.text.trim());
    final stops = await _api!.request('journey-stops');
    final saved = await _api!.request('saved-journeys');
    final sessions = await _api!.request('journey-sessions');
    if (!mounted) return;
    setState(() {
      _stops = stops['stops'] as List<dynamic>;
      _saved = saved['journeys'] as List<dynamic>;
      final active = sessions['sessions'] as List<dynamic>;
      _session = active.isEmpty ? null : active.first as Map<String,dynamic>;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
    await _poll();
  });

  Future<void> _search({bool replan = false}) => _run(() async {
    if (!replan && (_origin == null || _destination == null)) throw Exception('출발·도착 정류장을 선택해주세요.');
    final result = await _api!.request(replan ? 'journey-sessions/${_session!['id']}/replan' : 'journeys/search', body: replan ? {} : {
      'originStopId': _origin, 'destinationStopId': _destination,
      'departureAt': (_departNow ? DateTime.now() : _departure).toUtc().toIso8601String(), 'compareCount': 4,
      'compareStepMinutes': 15, 'maxTransfers': _transfers, 'bufferSeconds': 120,
    });
    if (mounted) setState(() { _comparisons = result['comparisons'] as List<dynamic>; _tab = 0; });
  });

  Future<void> _start(Map<String,dynamic> option) => _run(() async {
    if (_session != null) {
      throw Exception('현재 이동을 종료한 뒤 새 경로를 시작해주세요.');
    }
    final session = await _api!.request('journey-sessions', body: {'optionId': option['id']});
    if (mounted) setState(() { _session = session; _tab = 2; });
    await _poll();
  });

  Future<void> _action(String action) => _run(() async {
    final updated = await _api!.request('journey-sessions/${_session!['id']}/action', body: {
      'action': action, 'revision': _session!['revision'],
    });
    if (mounted) setState(() => _session = ['completed','cancelled'].contains(updated['status']) ? null : updated);
  });

  Future<void> _enableNotifications() => _run(() async {
    await _notifications.initialize(settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
      web: WebInitializationSettings(),
    ));
    bool granted = false;
    if (kIsWeb) {
      granted = await _notifications.resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      granted = await _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, sound: true) ?? false;
    }
    if (!granted) throw Exception('알림 권한을 확인해주세요.');
    if (mounted) setState(() => _notify = true);
    await _poll();
  });

  Future<void> _poll() async {
    if (_polling || _api == null || _session == null) return;
    _polling = true;
    try {
      final id = _session!['id'];
      final updated = await _api!.request('journey-sessions/$id');
      final result = await _api!.request('journey-sessions/$id/alerts');
      if (!mounted || _session?['id'] != id) return;
      setState(() => _session = updated);
      for (final raw in result['alerts'] as List<dynamic>) {
        final alert = raw as Map<String,dynamic>;
        final alertId = alert['id'] as String;
        if (_shown.contains(alertId)) continue;
        final text = '${alert['stopName']} · ${alert['routeName']} 버스 약 ${alert['etaMinutes']}분 후 도착 (${_basis(alert['basis'])})';
        if (_notify) {
          await _notifications.show(id: alertId.hashCode & 0x7fffffff,
            title: alert['kind'] == 'transfer' ? '환승 버스 도착 알림' : '승차 버스 도착 알림', body: text,
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails('journey_boarding', '승차·환승 알림', importance: Importance.max, priority: Priority.high),
              iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
              web: WebNotificationDetails(requireInteraction: true),
            ));
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 10)));
        _shown.add(alertId);
        await _api!.request('journey-sessions/$id/ack', body: {'ids': [alertId]});
      }
    } catch (e) { if (mounted) setState(() => _error = '이동 정보 갱신 실패: $e'); }
    finally { _polling = false; }
  }

  String _clock(dynamic time) {
    final date = DateTime.parse(time as String).toLocal();
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2,'0')}:${date.minute.toString().padLeft(2,'0')}';
  }
  String _basis(dynamic basis) => switch(basis) { 'realtime' => '실시간', 'headway' => '배차 추정', _ => '시간표' };
  String _minutes(dynamic seconds) => '${((seconds as num)/60).ceil()}분';
  Widget _card(Widget child) => Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(padding: const EdgeInsets.all(20), child: child));

  Future<void> _pickDeparture() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _departure.isBefore(now) ? now : _departure,
      firstDate: DateTime(now.year,now.month,now.day), lastDate: now.add(const Duration(days: 6)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_departure));
    if (time != null && mounted) setState(() { _departure = DateTime(date.year,date.month,date.day,time.hour,time.minute); _departNow = false; });
  }

  Future<void> _save() async {
    final name = TextEditingController();
    final days = <int>{1,2,3,4,5};
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
      title: const Text('출퇴근·등하교 경로 저장'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: '이름 (예: 회사 가는 길)')),
        const SizedBox(height: 12), Wrap(spacing: 4, children: List.generate(7,(i) => FilterChip(label: Text(['월','화','수','목','금','토','일'][i]), selected: days.contains(i+1), onSelected: (value) => update(() { value ? days.add(i+1) : days.remove(i+1); })))),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('저장'))],
    )));
    final title = name.text; name.dispose();
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _api!.request('saved-journeys', body: {'name': title, 'originStopId': _origin, 'destinationStopId': _destination,
        'weekdays': days.toList()..sort(), 'departureTime': '${_departure.hour.toString().padLeft(2,'0')}:${_departure.minute.toString().padLeft(2,'0')}'});
      final result = await _api!.request('saved-journeys');
      if (mounted) setState(() => _saved = result['journeys'] as List<dynamic>);
    });
  }

  Widget _settings() => _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('서버 연결', style: TextStyle(fontSize: 22,fontWeight: FontWeight.bold)),
    const SizedBox(height: 12), TextField(controller: _base, decoration: const InputDecoration(labelText: '앱 서버 주소')),
    const SizedBox(height: 12), TextField(controller: _token, obscureText: true, decoration: const InputDecoration(labelText: '개인 기기 토큰')),
    const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : _connect, child: const Text('연결')),
    const SizedBox(height: 12), const Text('기기 토큰은 서버 관리자가 발급합니다. 현재 연결 정보는 앱 종료 시 초기화됩니다.'),
    const Divider(), FilledButton.tonal(onPressed: _busy ? null : _enableNotifications, child: Text(_notify ? '알림 권한 확인 완료' : '승차·환승 알림 켜기')),
    const SizedBox(height: 12), const Text('현재 알림은 앱 또는 웹 화면이 실행 중일 때 확인합니다. 앱 종료 상태의 푸시 알림은 별도 연동이 필요합니다. 위치 권한은 필요하지 않습니다.'),
  ]));

  Widget _searchView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Text('오늘은 어떤 길로 갈까요?', style: TextStyle(fontSize: 24,fontWeight: FontWeight.bold)),
    const Text('직행과 환승, 출발 시간별 도착 시각을 비교하세요.'), const SizedBox(height: 16),
    if (_stops.isEmpty) const Text('정류장 데이터가 없습니다. 서버의 교통 데이터 등록 상태를 확인해주세요.'),
    TextField(decoration: const InputDecoration(labelText: '정류장 이름 검색', suffixIcon: Icon(Icons.search)), onSubmitted: (q) => _run(() async {
      final result = await _api!.request('journey-stops?q=${Uri.encodeQueryComponent(q)}');
      final selected = _stops.where((s) => s['id'] == _origin || s['id'] == _destination);
      final values = <String,dynamic>{for (final s in [...selected, ...(result['stops'] as List)]) s['id'] as String: s};
      if (mounted) setState(() => _stops = values.values.toList());
    })),
    const SizedBox(height: 12),
    _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(key: ValueKey('origin-$_origin'), initialValue: _origin, isExpanded: true, decoration: const InputDecoration(labelText: '출발 정류장'),
        items: _stops.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text('${s['name']} (${s['id']})',overflow: TextOverflow.ellipsis))).toList(),
        onChanged: _busy ? null : (v) => setState(() => _origin = v)),
      const SizedBox(height: 12), DropdownButtonFormField<String>(key: ValueKey('destination-$_destination'), initialValue: _destination,isExpanded: true,decoration: const InputDecoration(labelText: '목적 정류장'),
        items: _stops.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text('${s['name']} (${s['id']})',overflow: TextOverflow.ellipsis))).toList(),
        onChanged: _busy ? null : (v) => setState(() => _destination = v)),
      const SizedBox(height: 12), OutlinedButton(onPressed: _busy ? null : _pickDeparture, child: Text('출발 ${_clock(_departure.toIso8601String())}')),
      TextButton(onPressed: () => setState(() { _departure = DateTime.now(); _departNow = true; }), child: const Text('지금 출발')),
      SegmentedButton<int>(segments: const [ButtonSegment(value: 0,label: Text('직행')),ButtonSegment(value: 1,label: Text('환승 1회')),ButtonSegment(value: 2,label: Text('환승 2회'))], selected: {_transfers}, onSelectionChanged: _busy ? null : (s) => setState(() => _transfers = s.first)),
      const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : _search, child: const Text('15분 간격으로 경로 비교')),
      TextButton(onPressed: _busy || _origin == null || _destination == null ? null : _save, child: const Text('이 경로와 시간대 저장')),
    ])),
    for (final group in _comparisons) ...[
      Text('${_clock(group['departureAt'])} 출발', style: const TextStyle(fontSize: 19,fontWeight: FontWeight.bold)),
      if ((group['options'] as List).isEmpty) const Padding(padding: EdgeInsets.all(16),child: Text('이 시간대에 연결 가능한 경로가 없습니다.')),
      if (group['limited'] == true) const Text('검색량 제한으로 일부 후보만 표시합니다.'),
      for (final raw in group['options'] as List) _optionCard(raw as Map<String,dynamic>),
    ],
  ]);

  Widget _optionCard(Map<String,dynamic> option) => _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('${_clock(option['arrivalAt'])} 도착 · ${_minutes(option['durationSeconds'])}',style: const TextStyle(fontSize: 20,fontWeight: FontWeight.bold)),
    Text('환승 ${option['transfers']}회 · 대기 ${_minutes(option['waitSeconds'])} · 도보 ${_minutes(option['walkSeconds'])}'),
    for (final raw in option['legs'] as List) ...[
      const Divider(), Text('${raw['fromStopName']} → ${raw['toStopName']}'),
      Text('${raw['routeName']} · ${raw['direction']} · ${_clock(raw['departureAt'])} 승차'),
      Text('${_basis(raw['basis'])} · 대기 ${_minutes(raw['waitSeconds'])} · 환승 도보 ${_minutes(raw['walkSeconds'])} · 여유 ${_minutes(raw['bufferSeconds'])}'),
    ],
    const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : () => _start(option), child: const Text('이 버스 조합으로 이동 시작')),
  ]));

  Widget _savedView() => Column(children: [
    if (_saved.isEmpty) const Text('자주 가는 출퇴근·등하교 경로를 저장해보세요.'),
    for (final saved in _saved) _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
      Text(saved['name'] as String,style: const TextStyle(fontSize: 20,fontWeight: FontWeight.bold)),
      Text('${saved['origin_stop_id']} → ${saved['destination_stop_id']} · ${saved['departure_time']} (한국 시간)'),
      Text((jsonDecode(saved['weekdays'] as String) as List).map((d) => ['월','화','수','목','금','토','일'][(d as int)-1]).join(' · ')),
      FilledButton(onPressed: _busy ? null : () {
        final now = DateTime.now().toUtc().add(const Duration(hours: 9));
        final hhmm = (saved['departure_time'] as String).split(':');
        final weekdays = (jsonDecode(saved['weekdays'] as String) as List).cast<int>();
        var next = DateTime.utc(now.year,now.month,now.day,int.parse(hhmm[0]),int.parse(hhmm[1]));
        for (var n=0;n<8;n++) {
          if (next.isAfter(now) && weekdays.contains(next.weekday)) break;
          next = next.add(const Duration(days: 1));
        }
        setState(() { _origin = saved['origin_stop_id'] as String; _destination = saved['destination_stop_id'] as String;
          _departure = next.subtract(const Duration(hours: 9)).toLocal(); _departNow = false; _tab = 0; });
      },child: const Text('다음 이용 시간으로 검색 준비')),
      TextButton(onPressed: _busy ? null : () => _run(() async {
        await _api!.request('saved-journeys/${saved['id']}', method: 'DELETE');
        final result = await _api!.request('saved-journeys');
        if (mounted) setState(() => _saved = result['journeys'] as List<dynamic>);
      }),child: const Text('삭제')),
    ])),
  ]);

  Widget _activeView() {
    if (_session == null) return const Text('경로를 비교하고 이동을 시작해주세요.');
    final session = _session!, option = session['option'] as Map<String,dynamic>;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
      Text('이동 상태: ${switch(session['status']) {'waiting' => '첫 버스 대기', 'riding' => '탑승 중', 'transfer' => '환승 대기', 'disrupted' => '연결 재확인 필요', _ => session['status']}}',style: const TextStyle(fontSize: 22,fontWeight: FontWeight.bold)),
      Text('목적지 ${_clock(option['arrivalAt'])} 도착 예상'),
      for (var i=0;i<(option['legs'] as List).length;i++) ListTile(
        leading: Icon(i == session['currentLeg'] ? Icons.directions_bus : Icons.arrow_downward),
        title: Text('${option['legs'][i]['routeName']} · ${option['legs'][i]['fromStopName']} → ${option['legs'][i]['toStopName']}'),
        subtitle: Text('${_clock(option['legs'][i]['departureAt'])} · ${_basis(option['legs'][i]['basis'])}')),
      if (['waiting','transfer'].contains(session['status'])) ...[
        FilledButton(onPressed: _busy ? null : () => _action('board'),child: const Text('버스에 탑승했어요')),
        TextButton(onPressed: _busy ? null : () => _action('missed'),child: const Text('버스를 놓쳤어요')),
      ],
      if (session['status'] == 'riding') FilledButton(onPressed: _busy ? null : () => _action('alight'), child: const Text('하차했어요')),
      if (session['status'] == 'disrupted') OutlinedButton(onPressed: _busy ? null : () => _search(replan: true),child: const Text('현재 승차 정류장에서 대체 경로 비교')),
      TextButton(onPressed: _busy ? null : () => _action('cancel'),child: const Text('현재 이동 종료')),
      const Text('탑승·하차는 직접 확인해주세요. 지연 시 경로가 자동 변경되지는 않습니다.'),
    ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('버스 타이머'), actions: [IconButton(onPressed: () => setState(() => _tab = 3),icon: const Icon(Icons.settings))]),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760),child: ListView(padding: const EdgeInsets.all(20),children: [
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 16),child: Text(_error!,style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (_api == null || _tab == 3) _settings() else switch(_tab) {0 => _searchView(),1 => _savedView(),_ => _activeView()},
    ])))),
    bottomNavigationBar: NavigationBar(selectedIndex: _tab,onDestinationSelected: (v) => setState(() => _tab = v),destinations: const [
      NavigationDestination(icon: Icon(Icons.route),label: '홈'),NavigationDestination(icon: Icon(Icons.bookmark),label: '저장 경로'),
      NavigationDestination(icon: Icon(Icons.notifications),label: '이동·알림'),NavigationDestination(icon: Icon(Icons.settings),label: '설정'),
    ]),
  );
}
