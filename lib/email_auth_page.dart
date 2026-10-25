import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bus_data_service.dart';
import 'services/journey_service.dart';

class EmailAuthPage extends ConsumerStatefulWidget {
  const EmailAuthPage({super.key});
  @override
  ConsumerState<EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends ConsumerState<EmailAuthPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  JourneyService? _api;
  String? _account, _challenge, _error, _notice;
  bool _busy = false, _checking = false, _ready = false;
  String _mode = 'otp';
  Timer? _poll;
  DateTime? _linkExpires;
  DateTime? _resendAt;

  @override
  void initState() { super.initState(); _run(_load); }
  @override
  void dispose() { _poll?.cancel(); _email.dispose(); _code.dispose(); _api?.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try { await work(); }
    catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _load() async {
    _ready = false;
    _api?.dispose();
    _api = await JourneyService.connect();
    if (!mounted) { _api?.dispose(); return; }
    final config = await _api!.request('auth/config');
    final status = await _api!.request('auth/status');
    if (mounted) setState(() { _ready = true; _account = status['email'] as String?; _mode = config['mailAuthMode'] == 'link' ? 'link' : 'otp'; });
  }

  Future<void> _send() => _run(() async {
    if (_resendAt != null && DateTime.now().isBefore(_resendAt!)) {
      throw Exception('인증 메일 재전송은 1분 후에 가능합니다.');
    }
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw Exception('이메일 주소를 확인해주세요.');
    }
    final result = await _api!.request('auth/email-$_mode', body: {'email': email});
    if (mounted) setState(() {
      _challenge = result['challengeId'] as String;
      _resendAt = DateTime.now().add(const Duration(minutes: 1));
      _code.clear(); _notice = _mode == 'link' ? '인증 링크를 보냈습니다. 메일에서 인증한 뒤 이 화면으로 돌아와주세요.' : '인증번호를 보냈습니다. 10분 안에 입력해주세요.';
    });
    if (mounted && _mode == 'link') {
      _linkExpires = DateTime.now().add(const Duration(minutes: 10));
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _checkLink());
    }
  });

  Future<void> _checkLink() async {
    if (_checking || _busy || _api == null || _challenge == null) return;
    if (_linkExpires != null && DateTime.now().isAfter(_linkExpires!)) {
      _poll?.cancel();
      if (mounted) setState(() { _challenge = null; _notice = '인증 시간이 지났습니다. 메일을 다시 요청해주세요.'; });
      return;
    }
    _checking = true;
    final api = _api;
    try {
      final status = await api!.request('auth/status');
      if (!mounted || _api != api || _busy || status['email'] == null) return;
      _poll?.cancel();
      ref.read(busListProvider.notifier).replaceBuses([]);
      setState(() { _account = status['email'] as String; _challenge = null; _error = null; _notice = '이메일 인증이 완료되었습니다.'; });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally { _checking = false; }
  }

  Future<void> _verify() => _run(() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) throw Exception('6자리 인증번호를 입력해주세요.');
    await _api!.verifyEmail(_email.text.trim(), _code.text.trim(), _challenge!);
    ref.read(busListProvider.notifier).replaceBuses([]);
    await _load();
    if (mounted) setState(() { _challenge = null; _code.clear(); _notice = '이메일 인증이 완료되었습니다. 저장한 버스와 경로를 함께 사용할 수 있어요.'; });
  });

  Future<void> _logout() => _run(() async {
    _poll?.cancel();
    await _api!.logout();
    ref.read(busListProvider.notifier).replaceBuses([]);
    await _load();
    if (mounted) setState(() { _challenge = null; _email.clear(); _code.clear(); _notice = '로그아웃했습니다.'; });
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('이메일 인증')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('이메일로 인증하면 다른 기기에서도 저장한 버스와 경로를 불러올 수 있어요.'),
      const SizedBox(height: 24),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      if (_notice != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_notice!)),
      if (_account != null) ...[
        ListTile(leading: const Icon(Icons.verified_user_outlined), title: Text(_account!), subtitle: const Text('이메일 인증 완료')),
        OutlinedButton(onPressed: _busy ? null : _logout, child: const Text('로그아웃')),
      ] else ...[
        TextField(controller: _email, enabled: !_busy && _ready, keyboardType: TextInputType.emailAddress,
          autocorrect: false, decoration: const InputDecoration(labelText: '이메일 주소'),
          onChanged: (_) => setState(() { _poll?.cancel(); _challenge = null; _code.clear(); _notice = null; })),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy || !_ready ? null : _send, child: Text(_mode == 'link' ? (_challenge == null ? '인증 링크 받기' : '인증 링크 다시 받기') : (_challenge == null ? '인증번호 받기' : '인증번호 다시 받기'))),
        if (_mode == 'link' && _challenge != null)
          OutlinedButton(onPressed: _busy ? null : _checkLink, child: const Text('인증 완료 확인')),
        if (_mode == 'otp' && _challenge != null) ...[
          const SizedBox(height: 20),
          TextField(controller: _code, enabled: !_busy, keyboardType: TextInputType.number, maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode], decoration: const InputDecoration(labelText: '6자리 인증번호')),
          FilledButton(onPressed: _busy ? null : _verify, child: const Text('인증하고 로그인')),
        ],
        if (!_ready && !_busy) TextButton(onPressed: () => _run(_load), child: const Text('다시 연결')),
      ],
    ]),
  );
}
