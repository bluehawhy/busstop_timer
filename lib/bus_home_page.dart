import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_styles.dart';
import 'bus_data_service.dart';

class BusHomePage extends ConsumerStatefulWidget {
  const BusHomePage({super.key});

  @override
  ConsumerState<BusHomePage> createState() => _BusHomePageState();
}

class _BusHomePageState extends ConsumerState<BusHomePage> {
  int _selectedIndex = 0;
  final Map<String, bool> _alertEnabled = {};
  bool _previewNotifications = true;
  bool _locationPreview = false;

  static const _destinations = [
    _Destination('홈', Icons.home_rounded),
    _Destination('내 버스', Icons.directions_bus_rounded),
    _Destination('알림', Icons.notifications_rounded),
    _Destination('설정', Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final buses = ref.watch(busListProvider);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _desktopNavigation(),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: _pageForIndex(buses),
                      ),
                    ),
                  ),
                ],
              )
            : _pageForIndex(buses),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: _destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _desktopNavigation() {
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) =>
          setState(() => _selectedIndex = index),
      labelType: NavigationRailLabelType.all,
      backgroundColor: AppColors.surface,
      selectedIconTheme: const IconThemeData(color: AppColors.primary),
      selectedLabelTextStyle: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: AppColors.secondaryText,
      ),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.directions_bus_rounded,
            color: AppColors.accent,
          ),
        ),
      ),
      destinations: _destinations
          .map(
            (item) => NavigationRailDestination(
              icon: Icon(item.icon),
              label: Text(item.label),
            ),
          )
          .toList(),
    );
  }

  Widget _pageForIndex(List<BusArrivalInfo> buses) {
    switch (_selectedIndex) {
      case 1:
        return _myBusesPage(buses);
      case 2:
        return _alertsPage(buses);
      case 3:
        return _settingsPage();
      default:
        return _homePage(buses);
    }
  }

  Widget _pageFrame({
    required String title,
    String? subtitle,
    required Widget child,
    Widget? trailing,
  }) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.pageTitle),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          sliver: SliverToBoxAdapter(child: child),
        ),
      ],
    );
  }

  Widget _homePage(List<BusArrivalInfo> buses) {
    final nextBus = buses.isEmpty ? null : buses.first;
    return _pageFrame(
      title: '좋은 하루예요!',
      subtitle: '내 정류장 주변 버스 도착 정보를 확인해요.',
      trailing: IconButton(
        tooltip: '알림',
        onPressed: () => setState(() => _selectedIndex = 2),
        icon: const Icon(Icons.notifications_none_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _locationMapCard(),
          const SizedBox(height: 22),
          _sectionTitle('곧 도착하는 버스', action: '전체 보기', onAction: () {
            setState(() => _selectedIndex = 1);
          }),
          const SizedBox(height: 12),
          if (nextBus == null)
            _emptyBusesCard()
          else
            _upcomingBusCard(nextBus),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _quickAction(
                  icon: Icons.add_location_alt_outlined,
                  title: '정류장 찾기',
                  subtitle: '주변 정류장 등록',
                  onTap: _openStopSearch,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickAction(
                  icon: Icons.alarm_outlined,
                  title: '알림 시간',
                  subtitle: '요일과 시간 설정',
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _demoDataNote(),
        ],
      ),
    );
  }

  Widget _locationMapCard() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 245,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _MapStreetPainter()),
                ),
                Positioned(
                  top: 14,
                  left: 14,
                  child: _smallMapLabel(
                    _locationPreview ? '위치 미리보기' : '지도 미리보기',
                    Icons.map_outlined,
                  ),
                ),
                Center(
                  child: Container(
                    width: 166,
                    height: 166,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.10),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x22000000),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.directions_bus_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 34,
                  bottom: 44,
                  child: _mapPin(Icons.my_location_rounded, Colors.white),
                ),
                Positioned(
                  right: 28,
                  top: 84,
                  child: _mapPin(Icons.directions_bus_rounded, AppColors.accent),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: _smallMapLabel('30m', Icons.radar_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '내 정류장',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '정류장을 등록하면 주변 정보를 표시해요',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openStopSearch,
                  child: const Text('찾기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallMapLabel(String label, IconData icon) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapPin(IconData icon, Color color) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: Icon(icon, color: AppColors.primary, size: 17),
    );
  }

  Widget _upcomingBusCard(BusArrivalInfo bus) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _openArrival(bus),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _routeBadge(bus.busNum),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.station,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '다음 버스 · ${bus.nextBus ?? '도착 임박'}',
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _etaPill(bus.remain),
            ],
          ),
        ),
      ),
    );
  }

  Widget _myBusesPage(List<BusArrivalInfo> buses) {
    return _pageFrame(
      title: '내 버스',
      subtitle: '자주 타는 버스의 도착 정보를 모아봤어요.',
      trailing: IconButton.filled(
        tooltip: '버스 추가',
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        onPressed: _openStopSearch,
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: [
          if (buses.isEmpty)
            _emptyBusesCard()
          else
            ...buses.map(
              (bus) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Dismissible(
                  key: ValueKey(bus.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 22),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    ref.read(busListProvider.notifier).removeBus(bus);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${bus.busNum}번 버스를 삭제했어요.')),
                    );
                  },
                  child: _registeredBusCard(bus),
                ),
              ),
            ),
          const SizedBox(height: 8),
          _demoDataNote(),
        ],
      ),
    );
  }

  Widget _registeredBusCard(BusArrivalInfo bus) {
    final enabled = _alertEnabled[bus.id] ?? true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _routeBadge(bus.busNum),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bus.station, style: AppTextStyles.busNumber.copyWith(fontSize: 17)),
                      const SizedBox(height: 3),
                      const Text('등록한 정류장', style: AppTextStyles.stationName),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: enabled,
                  activeTrackColor: AppColors.primary,
                  onChanged: (value) =>
                      setState(() => _alertEnabled[bus.id] = value),
                ),
              ],
            ),
            const Divider(height: 26, color: AppColors.border),
            Row(
              children: [
                const Icon(Icons.directions_bus_filled_rounded, color: AppColors.primary),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    '이번 버스',
                    style: TextStyle(color: AppColors.secondaryText),
                  ),
                ),
                _etaPill(bus.remain),
              ],
            ),
            const SizedBox(height: 11),
            Row(
              children: [
                const Icon(Icons.more_time_rounded, color: AppColors.inactive),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text('다음 버스', style: TextStyle(color: AppColors.secondaryText)),
                ),
                Text(
                  bus.nextBus ?? '정보 없음',
                  style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showSchedule(bus),
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: const Text('알림 시간 설정'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertsPage(List<BusArrivalInfo> buses) {
    return _pageFrame(
      title: '알림 시간',
      subtitle: '등록한 시간 안에 버스가 5분 이내 도착하면 알려드려요.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: AppColors.primaryDark,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '5분 전 도착 알림',
                          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 5),
                        Text(
                          '정류장별로 시간과 요일을 설정할 수 있어요.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _sectionTitle('알림 받을 버스'),
          const SizedBox(height: 10),
          if (buses.isEmpty)
            _emptyBusesCard()
          else
            ...buses.map((bus) {
              final enabled = _alertEnabled[bus.id] ?? true;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    leading: _routeBadge(bus.busNum, compact: true),
                    title: Text(bus.station, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${bus.busNum}번 · 평일 오전 7:00–9:00'),
                    trailing: Switch.adaptive(
                      value: enabled,
                      activeTrackColor: AppColors.primary,
                      onChanged: (value) => setState(() => _alertEnabled[bus.id] = value),
                    ),
                    onTap: () => _showSchedule(bus),
                  ),
                ),
              );
            }),
          const SizedBox(height: 8),
          _infoCallout(
            icon: Icons.info_outline_rounded,
            title: '알림은 시안용 설정이에요',
            description: '현재 화면은 샘플 도착정보를 사용합니다. 푸시 알림과 실제 시간표 저장은 서버·권한 연동 후 동작합니다.',
          ),
        ],
      ),
    );
  }

  Widget _settingsPage() {
    return _pageFrame(
      title: '설정',
      subtitle: '알림과 위치 사용 방식을 확인할 수 있어요.',
      child: Column(
        children: [
          _settingsGroup(
            children: [
              _settingsRow(
                icon: Icons.notifications_active_outlined,
                title: '알림 미리보기',
                subtitle: '화면에서 알림 상태를 확인합니다',
                trailing: Switch.adaptive(
                  value: _previewNotifications,
                  activeTrackColor: AppColors.primary,
                  onChanged: (value) => setState(() => _previewNotifications = value),
                ),
              ),
              _settingsRow(
                icon: Icons.my_location_rounded,
                title: '위치 권한',
                subtitle: _locationPreview ? '미리보기 켜짐' : '기기 위치 연동 전',
                trailing: TextButton(
                  onPressed: () => setState(() => _locationPreview = !_locationPreview),
                  child: Text(_locationPreview ? '끄기' : '확인'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _infoCallout(
            icon: Icons.shield_outlined,
            title: '위치 정보 안내',
            description: '위치 권한과 정류장 반경 감지는 아직 실제 기기와 연결되지 않았습니다. 현재 30m 표시는 디자인 미리보기입니다.',
          ),
          const SizedBox(height: 14),
          _settingsGroup(
            children: [
              _settingsRow(
                icon: Icons.schedule_rounded,
                title: '알림 시간 관리',
                subtitle: '요일과 시간대별 알림을 설정해요',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inactive),
                onTap: () => setState(() => _selectedIndex = 2),
              ),
              _settingsRow(
                icon: Icons.privacy_tip_outlined,
                title: '개인정보 안내',
                subtitle: '위치 정보 이용 안내',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inactive),
                onTap: () => _showMessage(
                  '개인정보 안내',
                  '실제 위치 수집 및 보관 정책은 서버 연동 전 확정해야 합니다. 현재 버전은 위치 기록을 저장하지 않습니다.',
                ),
              ),
              _settingsRow(
                icon: Icons.help_outline_rounded,
                title: '도움말',
                subtitle: '서비스 사용 방법',
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.inactive),
                onTap: () => _showMessage(
                  '버스 타이머',
                  '정류장과 버스를 등록한 뒤 원하는 요일과 시간대를 설정하는 서비스 컨셉입니다.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '버스 타이머 · 디자인 프리뷰',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _settingsGroup({required List<Widget> children}) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 58, color: AppColors.border),
          ],
        ],
      ),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.secondaryText, fontSize: 12)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _infoCallout({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(description, style: const TextStyle(color: AppColors.secondaryText, height: 1.4, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: AppColors.secondaryText, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, {String? action, VoidCallback? onAction}) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: const TextStyle(color: AppColors.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }

  Widget _emptyBusesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: Center(
          child: Column(
            children: [
              const Icon(Icons.directions_bus_outlined, size: 38, color: AppColors.inactive),
              const SizedBox(height: 10),
              const Text('등록된 버스가 없어요', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('정류장과 버스를 찾아 알림을 설정해 보세요.', style: TextStyle(color: AppColors.secondaryText)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _openStopSearch,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('정류장 찾기'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _demoDataNote() {
    return const Text(
      '현재 도착 시간과 지도 표시는 화면 확인을 위한 샘플입니다.',
      style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
      textAlign: TextAlign.center,
    );
  }

  Widget _routeBadge(String route, {bool compact = false}) {
    final color = int.tryParse(route) != null && int.parse(route) % 2 == 0
        ? AppColors.routeBlue
        : AppColors.primary;
    return Container(
      width: compact ? 48 : 62,
      height: compact ? 42 : 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 13 : 16),
      ),
      child: Text(
        route,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: compact ? 15 : 18,
        ),
      ),
    );
  }

  Widget _etaPill(String eta) {
    final soon = eta.contains('곧') || eta.startsWith('1') || eta.startsWith('2') || eta.startsWith('3');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: soon ? AppColors.accent.withValues(alpha: 0.55) : AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        eta,
        style: TextStyle(
          color: soon ? AppColors.primaryDark : AppColors.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Future<void> _showSchedule(BusArrivalInfo bus) async {
    final periods = ['1분 전', '3분 전', '5분 전', '10분 전'];
    var selected = '5분 전';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.background,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${bus.busNum}번 알림 시간', style: AppTextStyles.pageTitle.copyWith(fontSize: 21)),
              const SizedBox(height: 5),
              Text(bus.station, style: const TextStyle(color: AppColors.secondaryText)),
              const SizedBox(height: 20),
              const Text('도착 알림 시점', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
              const SizedBox(height: 8),
              for (final period in periods)
                RadioListTile<String>(
                  value: period,
                  groupValue: selected,
                  activeColor: AppColors.primary,
                  title: Text(period),
                  onChanged: (value) {
                    if (value != null) setSheetState(() => selected = value);
                  },
                ),
              const SizedBox(height: 8),
              const Text('알림 시간대: 평일 오전 7:00–9:00 (샘플)', style: TextStyle(color: AppColors.secondaryText)),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('설정 미리보기에 반영했어요.')),
                    );
                  },
                  child: const Text('저장'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openStopSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddBusPage()),
    );
  }

  void _openArrival(BusArrivalInfo bus) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArrivalAlertPage(bus: bus),
      ),
    );
  }

  Future<void> _showMessage(String title, String body) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

class ArrivalAlertPage extends StatelessWidget {
  const ArrivalAlertPage({super.key, required this.bus});

  final BusArrivalInfo bus;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        title: const Text('도착 알림 미리보기'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_active_rounded, color: AppColors.accent, size: 30),
                  ),
                  const SizedBox(height: 18),
                  const Text('버스 도착 알림', style: TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 8),
                  Text(
                    '${bus.remain} 후 도착',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${bus.busNum}번 버스가 곧 도착합니다.',
                    style: const TextStyle(color: Colors.white, fontSize: 17),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.directions_bus_rounded, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '${bus.busNum}번 버스',
                                  style: AppTextStyles.busNumber.copyWith(fontSize: 20),
                                ),
                              ),
                              const Text('샘플 정보', style: TextStyle(color: AppColors.secondaryText, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _stopMarker('이전 정류장', false),
                              const Expanded(child: Divider(color: AppColors.primary)),
                              _stopMarker('내 정류장', true),
                              const Expanded(child: Divider(color: AppColors.border)),
                              _stopMarker('다음 정류장', false),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(bus.station, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '실제 도착 예측과 푸시 발송은 교통정보 API 및 알림 서비스 연결 후 제공됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.primaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('확인'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stopMarker(String label, bool active) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          Icon(
            active ? Icons.location_on_rounded : Icons.circle,
            color: active ? AppColors.primary : AppColors.inactive,
            size: active ? 24 : 13,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? AppColors.primary : AppColors.secondaryText,
              fontSize: 10,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AddBusPage extends ConsumerStatefulWidget {
  const AddBusPage({super.key});

  @override
  ConsumerState<AddBusPage> createState() => _AddBusPageState();
}

class _AddBusPageState extends ConsumerState<AddBusPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  final List<Map<String, String>> _nearbyStations = const [
    {'name': '부산역 (중앙대로)', 'distance': '85m', 'id': '01001'},
    {'name': '초량역 1번 출구', 'distance': '120m', 'id': '01002'},
    {'name': '서면역', 'distance': '240m', 'id': '01003'},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filteredStations {
    final keyword = _searchKeyword.trim().toLowerCase();
    if (keyword.isEmpty) return _nearbyStations;
    return _nearbyStations.where((station) {
      return station['name']!.toLowerCase().contains(keyword) ||
          station['id']!.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final registered = ref.watch(busListProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('정류장 찾기')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _searchKeyword = value),
                  decoration: const InputDecoration(
                    hintText: '정류장 이름 또는 ID 검색',
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: Icon(Icons.tune_rounded),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('주변 정류장', style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800)),
                    ),
                    Text(
                      '위치 샘플',
                      style: TextStyle(color: AppColors.primary.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                  itemCount: _filteredStations.length,
                  itemBuilder: (context, index) {
                    final station = _filteredStations[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        shape: const Border(),
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.directions_bus_rounded, color: AppColors.primary),
                        ),
                        title: Text(
                          station['name']!,
                          style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('정류장 ID ${station['id']} · ${station['distance']}'),
                        children: [
                          for (final route in ['179', '1000'])
                            _routeChoice(station['name']!, route, registered),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: const Text(
                  '정류장·노선은 화면 확인용 샘플입니다. 실제 검색은 교통정보 API 연동 후 제공됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.secondaryText, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeChoice(
    String station,
    String route,
    List<BusArrivalInfo> registered,
  ) {
    final bus = BusArrivalInfo(
      station: station,
      busNum: route,
      remain: route == '179' ? '5분 30초' : '3분',
      nextBus: route == '179' ? '12분' : null,
    );
    final exists = registered.any((item) => item.id == bus.id);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 22, right: 14),
      leading: Container(
        width: 44,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: route == '179' ? AppColors.routeBlue : AppColors.primary,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(route, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
      ),
      title: Text('$route번 버스'),
      subtitle: Text('이번 버스 · ${bus.remain}'),
      trailing: IconButton(
        tooltip: exists ? '이미 등록됨' : '버스 등록',
        onPressed: exists
            ? null
            : () {
                ref.read(busListProvider.notifier).addBus(bus);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$route번 버스를 등록했어요.')),
                );
              },
        icon: Icon(
          exists ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
          color: exists ? AppColors.success : AppColors.primary,
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _MapStreetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final park = Paint()..color = const Color(0xFFE7F0DF);
    final water = Paint()..color = const Color(0xFFDDEEF0);
    final road = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..strokeWidth = 18
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadEdge = Paint()
      ..color = const Color(0xFFD9E0D9)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF0F2E9));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.04, size.height * 0.08, size.width * 0.23, size.height * 0.24),
        const Radius.circular(24),
      ),
      park,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.73, size.height * 0.57, size.width * 0.22, size.height * 0.28),
        const Radius.circular(24),
      ),
      park,
    );
    final river = Path()
      ..moveTo(size.width * 0.86, 0)
      ..cubicTo(size.width * 0.76, size.height * 0.25, size.width * 0.96, size.height * 0.55, size.width * 0.82, size.height)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(river, water);

    for (var i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 18), road,);
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 18), roadEdge);
    }
    for (var i = 1; i <= 3; i++) {
      final x = size.width * (i / 4);
      canvas.drawLine(Offset(x, 0), Offset(x - 24, size.height), road);
      canvas.drawLine(Offset(x, 0), Offset(x - 24, size.height), roadEdge);
    }

    final route = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.85)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final routePath = Path()
      ..moveTo(size.width * 0.25, size.height * 1.05)
      ..cubicTo(size.width * 0.38, size.height * 0.75, size.width * 0.37, size.height * 0.45, size.width * 0.57, size.height * -0.1);
    canvas.drawPath(routePath, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
