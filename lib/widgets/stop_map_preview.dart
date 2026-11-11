import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app_styles.dart';
import '../bus_data_service.dart';
import '../services/journey_service.dart';
import 'busan_map_regions.dart';
import 'bus_stop_marker.dart';

/// Real OSM vector map and stop catalog. Vehicle icons and route polylines are
/// deliberately omitted unless authoritative coordinates are available.
class StopMapPreview extends ConsumerStatefulWidget {
  const StopMapPreview({
    super.key,
    required this.region,
    this.route,
    this.arrival,
    this.onBusTap,
    this.onStopChanged,
    this.onRouteChanged,
  });

  final BusanMapRegion region;
  final String? route;
  final String? arrival;
  final VoidCallback? onBusTap;
  final ValueChanged<Map<String, dynamic>?>? onStopChanged;
  final ValueChanged<Map<String, dynamic>?>? onRouteChanged;

  @override
  ConsumerState<StopMapPreview> createState() => _StopMapPreviewState();
}

class _StopMapPreviewState extends ConsumerState<StopMapPreview> {
  static const _normalIcon = 'bus-stop-teal';
  static const _selectedIcon = 'bus-stop-orange';
  static const _routeBlue = '#246BFA';

  MapLibreMapController? _map;
  JourneyService? _api;
  bool _ready = false, _loading = false, _pending = false, _zoomRequired = false;
  bool _truncated = false, _saving = false;

  String? _error, _routeNotice;
  Map<String, dynamic>? _selectedStop, _selectedRoute;
  List<Map<String, dynamic>> _routes = [];
  final Map<String, Map<String, dynamic>> _stopsBySymbol = {};
  final Map<String, Symbol> _stopSymbols = {};

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }

  Future<JourneyService> _service() async {
    final current = _api;
    if (current != null) return current;
    final opened = await JourneyService.connect();
    if (!mounted) {
      opened.dispose();
      throw StateError('Map closed');
    }
    _api = opened;
    return opened;
  }

  @override
  void didUpdateWidget(covariant StopMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.region.district == widget.region.district) return;
    _selectedStop = null;
    _selectedRoute = null;
    _routes = [];
    _routeNotice = null;
    _map?.clearLines();
    _map?.animateCamera(
      CameraUpdate.newLatLngZoom(widget.region.center, 14),
    );
  }

  void _onMapCreated(MapLibreMapController map) {
    _map = map;
    map.onSymbolTapped.add((symbol) {
      final stop = _stopsBySymbol[symbol.id];
      if (stop != null) _selectStop(stop);
    });
  }

  Future<void> _onStyleReady() async {
    final controller = _map;
    if (controller == null) return;
    try {
      await controller.addImage(
        _normalIcon, await createBusStopMarker(selected: false),
      );
      await controller.addImage(
        _selectedIcon, await createBusStopMarker(selected: true),
      );
      if (!mounted || !identical(_map, controller)) return;
      _ready = true;
      await _refreshVisibleStops();
    } catch (_) {
      if (mounted) setState(
        () => _error = '지도 정류장 아이콘을 불러오지 못했어요.',
      );
    }
  }

  Future<void> _refreshVisibleStops() async {
    final controller = _map;
    if (controller == null || !_ready) return;
    if (_loading) {
      _pending = true;
      return;
    }
    _loading = true;
    try {
      final bounds = await controller.getVisibleRegion();
      final south = bounds.southwest.latitude;
      final north = bounds.northeast.latitude;
      final west = bounds.southwest.longitude;
      final east = bounds.northeast.longitude;
      // At a city-wide scale the catalog would overwhelm the mobile map.
      if (north - south > 0.4 || east - west > 0.4 ||
          south >= north || west >= east) {
        await controller.clearSymbols();
        _stopsBySymbol.clear();
        _stopSymbols.clear();
        if (mounted) setState(() {
          _zoomRequired = true;
          _truncated = false;
          _error = null;
        });
        return;
      }
      final api = await _service();
      final query = Uri(queryParameters: {
        'south': '$south',
        'north': '$north',
        'west': '$west',
        'east': '$east',
      }).query;
      final result = await api.request('bus/map/stops?$query');
      if (!mounted || !identical(controller, _map)) return;
      final stops = (result['stops'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .where((stop) => stop['latitude'] is num && stop['longitude'] is num)
          .toList();
      await controller.clearSymbols();
      _stopsBySymbol.clear();
      _stopSymbols.clear();
      // Bus-front pictograms from concept 4, with collision-safe symbols.
      final markers = await controller.addSymbols([
        for (final stop in stops)
          SymbolOptions(
            geometry: LatLng(
              (stop['latitude'] as num).toDouble(),
              (stop['longitude'] as num).toDouble(),
            ),
            iconImage: stop['id'] == _selectedStop?['id']
                ? _selectedIcon : _normalIcon,
            iconSize: stop['id'] == _selectedStop?['id'] ? 0.60 : 0.43,
          ),
      ]);
      for (var i = 0; i < markers.length; i++) {
        _stopsBySymbol[markers[i].id] = stops[i];
        _stopSymbols['${stops[i]['id']}'] = markers[i];
      }
      // Only label nearby stops at close zoom; dense numbers must not
      // compete with the map title or the selected route.
      if (north - south < 0.018) {
        final named = north - south < 0.009;
        final labelled = stops.take(named ? 25 : 18).toList();
        final symbols = await controller.addSymbols([
          for (final stop in labelled)
            SymbolOptions(
              geometry: LatLng((stop['latitude'] as num).toDouble(),
                (stop['longitude'] as num).toDouble()),
              textField: named ? '${stop['name']}'
                : (stop['arsNo']?.toString() ?? ''),
              textSize: named ? 10.5 : 10,
              textColor: '#566A72',
              textHaloColor: '#F9FDFB',
              textHaloWidth: 1.8,
              textAnchor: 'top',
              textOffset: const Offset(0, 0.9),
            ),
        ]);
        for (var i = 0; i < symbols.length; i++) {
          _stopsBySymbol[symbols[i].id] = labelled[i];
        }
      }
      if (mounted) setState(() {
        _zoomRequired = result['zoomRequired'] == true;
        _truncated = result['truncated'] == true;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '정류장 위치를 불러오지 못했어요.');
    } finally {
      _loading = false;
      if (_pending && mounted) {
        _pending = false;
        _refreshVisibleStops();
      }
    }
  }

  Future<void> _selectStop(Map<String, dynamic> stop) async {
    final controller = _map;
    final previous = _stopSymbols['${_selectedStop?['id']}'];
    if (previous != null && controller != null) {
      await controller.updateSymbol(previous, const SymbolOptions(
        iconImage: _normalIcon, iconSize: 0.43,
      ));
    }
    final selected = _stopSymbols['${stop['id']}'];
    if (selected != null && controller != null) {
      await controller.updateSymbol(selected, const SymbolOptions(
        iconImage: _selectedIcon, iconSize: 0.60,
      ));
    }
    if (!mounted) return;
    setState(() {
      _selectedStop = stop;
      _selectedRoute = null;
      _routes = [];
      _routeNotice = '정류장 노선을 조회하고 있어요.';
    });
    widget.onStopChanged?.call(stop);
    widget.onRouteChanged?.call(null);
    await controller?.clearLines();
    try {
      final api = await _service();
      final result = await api.request('bus/routes?${Uri(queryParameters: {
        'stopId': '${stop['id']}',
      }).query}');
      if (!mounted || _selectedStop?['id'] != stop['id']) return;
      setState(() {
        _routes = (result['routes'] as List<dynamic>? ?? [])
            .map((r) => Map<String, dynamic>.from(r as Map)).toList();
        _routeNotice = _routes.isEmpty
            ? '조회된 노선이 없습니다.' : '노선을 선택해 경로를 확인하세요.';
      });
    } catch (_) {
      if (mounted && _selectedStop?['id'] == stop['id']) {
        setState(() => _routeNotice = '노선을 불러오지 못했습니다. 다시 시도해주세요.');
      }
    }
  }

  Future<void> _selectRoute(Map<String, dynamic> route) async {
    final id = route['routeId']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() {
      _selectedRoute = route;
      _routeNotice = '확인된 노선 경로를 조회하고 있어요.';
    });
    widget.onRouteChanged?.call(route);
    final controller = _map;
    await controller?.clearLines();
    try {
      final api = await _service();
      final result = await api.request('bus/map/route?${Uri(queryParameters: {
        'routeId': id,
      }).query}');
      if (!mounted || _selectedRoute?['routeId'] != id) return;
      final geometry = result['geometry'];
      if (result['verified'] != true || geometry is! Map ||
          geometry['type'] != 'LineString') {
        setState(() => _routeNotice = '공식 노선 경로 데이터가 아직 없어요. 정류장 위치만 표시합니다.');
        return;
      }
      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) {
        setState(() => _routeNotice = '노선 경로 좌표를 확인할 수 없어요.');
        return;
      }
      final points = <LatLng>[];
      for (final item in coordinates) {
        if (item is! List || item.length != 2 ||
            item[0] is! num || item[1] is! num) return;
        points.add(LatLng((item[1] as num).toDouble(), (item[0] as num).toDouble()));
      }
      // A neutral border separates the verified transit route from roads.
      await controller?.addLine(LineOptions(
        geometry: points,
        lineColor: '#FFFFFF',
        lineWidth: 10,
        lineOpacity: 0.98,
      ));
      await controller?.addLine(LineOptions(
        geometry: points,
        lineColor: _routeBlue,
        lineWidth: 6,
        lineOpacity: 0.96,
      ));
      if (mounted) setState(() => _routeNotice = '확인된 경로 · ${result['source']}');
    } catch (_) {
      if (mounted) setState(() => _routeNotice = '노선 경로를 조회하지 못했어요.');
    }
  }

  Future<void> _saveRoute() async {
    if (_saving || _selectedStop == null || _selectedRoute == null) return;
    setState(() => _saving = true);
    try {
      final api = await _service();
      final saved = await api.request('bus/subscriptions', body: {
        'stopId': _selectedStop!['id'],
        'routeId': _selectedRoute!['routeId'],
      });
      if (!mounted) return;
      final name = _selectedStop!['name'].toString();
      final number = _selectedRoute!['routeName'].toString();
      // Preserve the registration on the home tab without inventing an ETA.
      ref.read(busListProvider.notifier).addBus(BusArrivalInfo(
        recordId: '${saved['id']}',
        station: name, busNum: number, remain: '도착정보 조회 필요',
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name · $number 노선을 저장했어요.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장 실패: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _closeStop() {
    _map?.clearLines();
    widget.onStopChanged?.call(null);
    widget.onRouteChanged?.call(null);
    setState(() {
      _selectedStop = null;
      _selectedRoute = null;
      _routes = [];
      _routeNotice = null;
    });
    _refreshVisibleStops();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(child: MapLibreMap(
        initialCameraPosition: CameraPosition(target: widget.region.center, zoom: 14),
        styleString: 'assets/map/bus_transit_style.json',
        onMapCreated: _onMapCreated,
        onStyleLoadedCallback: _onStyleReady,
        onCameraIdle: () { _refreshVisibleStops(); },
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        compassEnabled: false,
      )),
      // Keep map credits visible above the draggable bottom sheet.
      const Positioned(top: 127, right: 10, child: IgnorePointer(
        child: Text('© OpenFreeMap · OpenMapTiles · OpenStreetMap',
          style: TextStyle(fontSize: 9, color: Color(0xFF637083),
            shadows: [Shadow(color: Colors.white, blurRadius: 4)])),
      )),
      if (widget.route != null && _selectedStop == null)
        Positioned(top: 152, left: 14, child: ActionChip(
          label: Text('${widget.route} · ${widget.arrival ?? '도착정보 없음'}'),
          avatar: const Icon(Icons.directions_bus_rounded,
            color: AppColors.primary, size: 17),
          onPressed: widget.onBusTap,
        )),
      if (_error != null || _zoomRequired || _truncated)
        Positioned(top: _selectedStop == null ? 192 : 317, left: 16, right: 16,
          child: IgnorePointer(child: Center(child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(_error ?? (_zoomRequired
                ? '확대하면 정류장이 표시됩니다.'
                : '정류장이 많은 지역이에요. 확대해 확인하세요.'),
                style: const TextStyle(fontSize: 11, color: AppColors.secondaryText)),
            ),
          )))),
      if (_selectedStop != null)
        Positioned(top: 148, left: 12, right: 12, child: Material(
          color: Colors.white, elevation: 5, borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(constraints: const BoxConstraints(maxHeight: 187),
            child: SingleChildScrollView(padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${_selectedStop!['name']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  IconButton(icon: const Icon(Icons.close, size: 18),
                    tooltip: '정류장 닫기', onPressed: _closeStop,
                    visualDensity: VisualDensity.compact),
                ]),
                if (_selectedStop!['arsNo'] != null)
                  Text('정류장 번호 ${_selectedStop!['arsNo']}',
                    style: const TextStyle(fontSize: 11, color: AppColors.secondaryText)),
                const SizedBox(height: 7),
                if (_routes.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final route in _routes.take(12))
                    ChoiceChip(
                      label: Text('${route['routeName']}', style: const TextStyle(fontSize: 12)),
                      selected: _selectedRoute?['routeId'] == route['routeId'],
                      selectedColor: const Color(0xFFE9F2FF),
                      onSelected: (_) => _selectRoute(route),
                      avatar: CircleAvatar(radius: 5,
                        backgroundColor: Color(int.parse(
                          _routeBlue.substring(1), radix: 16) | 0xFF000000)),
                    ),
                ]),
                if (_routeNotice != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_routeNotice!, style: const TextStyle(fontSize: 11,
                    color: AppColors.secondaryText))),
                if (_selectedRoute != null) Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(onPressed: _saving ? null : _saveRoute,
                    icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                    label: const Text('내 버스에 등록')),
                ),
              ])),
          ),
        )),
    ]);
  }
}
