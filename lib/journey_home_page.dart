import 'email_auth_page.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/journey_service.dart';
import 'app_styles.dart';

class JourneyHomePage extends StatefulWidget {
  const JourneyHomePage({super.key});
  @override
  State<JourneyHomePage> createState() => _JourneyHomePageState();
}

class _JourneyHomePageState extends State<JourneyHomePage> {
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
  void initState() { super.initState(); _connect(); }

  @override
  void dispose() {
    _timer?.cancel(); _api?.dispose(); _base.dispose();
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
    if (uri == null || !uri.hasAuthority || !['http','https'].contains(uri.scheme)) {
      throw Exception('서버 주소를 확인해주세요.');
    }
    _api?.dispose(); _api = await JourneyService.connect(baseUrl: _base.text.trim());
    if (!mounted) { _api?.dispose(); return; }
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
  Widget _card(Widget child) => Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(padding: const EdgeInsets.all(24), child: child));

  Widget _heading(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: AppTextStyles.pageTitle),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(color: AppColors.secondaryText, height: 1.6)),
    ]),
  );

  Widget _notice(IconData icon, String title, String message) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(22)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppColors.primary), const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6), Text(message, style: const TextStyle(color: AppColors.secondaryText, height: 1.6)),
      ])),
    ]),
  );

  Widget _hero() => Container(
    margin: const EdgeInsets.only(bottom: 24), padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppColors.primaryDark, AppColors.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
          child: const Text('매일의 이동을 가볍게', style: TextStyle(color: AppColors.primaryDark, fontSize: 12, fontWeight: FontWeight.w800))),
        const Spacer(), const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 32),
      ]),
      const SizedBox(height: 24),
      const Text('오늘은 어떤 길로 갈까요?', style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
      const SizedBox(height: 10),
      const Text('직행부터 환승까지, 나에게 맞는 경로를 찾아요.', style: TextStyle(color: Color(0xFFD7ECE8), height: 1.6)),
      const SizedBox(height: 22),
      const Row(children: [Icon(Icons.notifications_active_outlined, color: AppColors.accent, size: 19), SizedBox(width: 8),
        Expanded(child: Text('승차·환승 버스 도착 5분 전 안내', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)))]),
    ]),
  );

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
    _heading('설정', '연결과 알림을 관리해요.'),
    const Text('서버는 자동으로 연결됩니다. 이메일 인증으로 다른 기기에서도 저장한 경로를 불러올 수 있어요.'),
    const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : () async {
      _timer?.cancel();
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EmailAuthPage()));
      if (!mounted) return;
      setState(() { _comparisons = []; _saved = []; _session = null; _shown.clear(); });
      await _connect();
    }, child: const Text('이메일 인증 · 계정 관리')),
    const SizedBox(height: 12), OutlinedButton(onPressed: _busy ? null : _connect, child: const Text('다시 연결')),
    const Divider(), FilledButton.tonal(onPressed: _busy ? null : _enableNotifications, child: Text(_notify ? '알림 권한 확인 완료' : '승차·환승 알림 켜기')),
    const SizedBox(height: 12), const Text('현재 알림은 앱 또는 웹 화면이 실행 중일 때 확인합니다. 앱 종료 상태의 푸시 알림은 별도 연동이 필요합니다. 위치 권한은 필요하지 않습니다.'),
  ]));

  Widget _searchView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _hero(),
    _heading('어디로 이동하시나요?', '출발지와 목적지를 선택하고 도착 시간을 비교해보세요.'),
    if (_stops.isEmpty) const Text('정류장 데이터가 없습니다. 서버의 교통 데이터 등록 상태를 확인해주세요.'),
    TextField(decoration: const InputDecoration(labelText: '정류장 이름 검색', suffixIcon: Icon(Icons.search)), onSubmitted: (q) => _run(() async {
      final result = await _api!.request('journey-stops?q=${Uri.encodeQueryComponent(q)}');
      final selected = _stops.where((s) => s['id'] == _origin || s['id'] == _destination);
      final values = <String,dynamic>{for (final s in [...selected, ...(result['stops'] as List)]) s['id'] as String: s};
      if (mounted) setState(() => _stops = values.values.toList());
    })),
    const SizedBox(height: 12),
    _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(key: ValueKey('origin-$_origin'), initialValue: _origin, isExpanded: true, decoration: const InputDecoration(labelText: '출발 정류장', prefixIcon: Icon(Icons.trip_origin, color: AppColors.primary)),
        items: _stops.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text('${s['name']} (${s['id']})',overflow: TextOverflow.ellipsis))).toList(),
        onChanged: _busy ? null : (v) => setState(() => _origin = v)),
      Align(alignment: Alignment.centerRight, child: IconButton(tooltip: '출발지와 목적지 바꾸기', onPressed: _busy ? null : () => setState(() { final previous = _origin; _origin = _destination; _destination = previous; }), icon: const Icon(Icons.swap_vert_rounded, color: AppColors.primary))), DropdownButtonFormField<String>(key: ValueKey('destination-$_destination'), initialValue: _destination,isExpanded: true,decoration: const InputDecoration(labelText: '목적 정류장', prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.primary)),
        items: _stops.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text('${s['name']} (${s['id']})',overflow: TextOverflow.ellipsis))).toList(),
        onChanged: _busy ? null : (v) => setState(() => _destination = v)),
      const SizedBox(height: 12), OutlinedButton(onPressed: _busy ? null : _pickDeparture, child: Text(_departNow ? '지금 출발 · 시간 변경' : '출발 ${_clock(_departure.toIso8601String())}')),
      TextButton(onPressed: () => setState(() { _departure = DateTime.now(); _departNow = true; }), child: const Text('지금 출발')),
      SegmentedButton<int>(segments: const [ButtonSegment(value: 0,label: Text('직행')),ButtonSegment(value: 1,label: Text('환승 1회')),ButtonSegment(value: 2,label: Text('환승 2회'))], selected: {_transfers}, onSelectionChanged: _busy ? null : (s) => setState(() => _transfers = s.first)),
      const SizedBox(height: 16), FilledButton(onPressed: _busy ? null : _search, child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.search_rounded), SizedBox(width: 8), Text('15분 간격으로 경로 비교')])),
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
      const Divider(),
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.directions_bus_rounded, size: 18, color: Colors.white), const SizedBox(width: 6), Text('${raw['routeName']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))])),
        const SizedBox(width: 10), Expanded(child: Text('${raw['direction']}', style: const TextStyle(color: AppColors.secondaryText))),
      ]),
      const SizedBox(height: 12),
      Text('${raw['fromStopName']} → ${raw['toStopName']}', style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('${_clock(raw['departureAt'])} 승차'),
      Text('${_basis(raw['basis'])} · 대기 ${_minutes(raw['waitSeconds'])} · 환승 도보 ${_minutes(raw['walkSeconds'])} · 여유 ${_minutes(raw['bufferSeconds'])}'),
    ],
    const SizedBox(height: 12), FilledButton(onPressed: _busy ? null : () => _start(option), child: const Text('이 버스 조합으로 이동 시작')),
  ]));

  Widget _savedView() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _heading('나의 저장 경로', '자주 가는 길, 매번 입력하지 않아도 돼요.'),
    if (_saved.isEmpty) _notice(Icons.bookmark_border_rounded, '아직 저장한 경로가 없어요', '홈에서 출발지와 목적지를 선택한 뒤 경로와 시간대를 저장해주세요.'),
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
    if (_session == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _heading('이동·알림', '승차부터 환승까지 함께할게요.'),
      _notice(Icons.directions_bus_outlined, '아직 시작한 이동이 없어요', '홈에서 경로를 비교하고 이동을 시작하면 구간별 승차 정보를 확인할 수 있어요.'),
      FilledButton(onPressed: () => setState(() => _tab = 0), child: const Text('이동 경로 찾기')),
    ]);
    }
    final session = _session!, option = session['option'] as Map<String,dynamic>;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch,children: [
      _notice(Icons.notifications_active_rounded, '이동 중에도 놓치지 않도록', '각 구간의 버스 도착 5분 전에 안내해요. 알림 권한은 설정에서 켤 수 있어요.'),
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

  Widget _navigation(bool wide) {
    const destinations = [
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: '홈'),
      NavigationDestination(icon: Icon(Icons.bookmark_border_rounded), selectedIcon: Icon(Icons.bookmark_rounded), label: '저장 경로'),
      NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications_rounded), label: '이동·알림'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: '설정'),
    ];
    if (!wide) return NavigationBar(selectedIndex: _tab, onDestinationSelected: (v) => setState(() => _tab = v), destinations: destinations);
    return NavigationRail(
      backgroundColor: AppColors.primaryDark, selectedIndex: _tab,
      onDestinationSelected: (v) => setState(() => _tab = v),
      labelType: NavigationRailLabelType.all, indicatorColor: AppColors.accent,
      selectedIconTheme: const IconThemeData(color: AppColors.primaryDark),
      unselectedIconTheme: const IconThemeData(color: Color(0xFFBDD7D3)),
      selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: const TextStyle(color: Color(0xFFBDD7D3)),
      leading: const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Icon(Icons.directions_bus_rounded, color: AppColors.accent, size: 32)),
      destinations: destinations.map((d) => NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth >= 900;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        title: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.directions_bus_rounded, color: AppColors.primary), SizedBox(width: 10), Text('버스 타이머', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21))]),
        actions: [Padding(padding: const EdgeInsets.only(right: 16), child: IconButton(tooltip: '설정', onPressed: () => setState(() => _tab = 3), icon: const Icon(Icons.settings_outlined)))],
      ),
      body: SafeArea(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (wide) _navigation(true),
        Expanded(child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: wide ? 920 : 760), child: ListView(
          padding: EdgeInsets.all(wide ? 36 : 20), children: [
            if (_busy) const Padding(padding: EdgeInsets.only(bottom: 16), child: LinearProgressIndicator()),
            if (_error != null) Semantics(liveRegion: true, child: _notice(Icons.error_outline, '확인이 필요해요', _error!)),
            if (_api == null || _tab == 3) _settings() else switch(_tab) {0 => _searchView(),1 => _savedView(),_ => _activeView()},
          ],
        )))),
      ])),
      bottomNavigationBar: wide ? null : _navigation(false),
    );
  });
}
