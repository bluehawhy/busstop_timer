// lib/bus_data_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

class BusArrivalInfo {
  final String? recordId;
  final String station;
  final String busNum;
  final String remain;
  final String? nextBus;

  const BusArrivalInfo({
    this.recordId,
    required this.station,
    required this.busNum,
    required this.remain,
    this.nextBus,
  });

  // Display adapter for preview ordering; live arrivals can replace the provider.
  int get etaSeconds {
    if (remain.contains('곧')) return 0;
    final minutes = int.tryParse(RegExp(r'(\d+)분').firstMatch(remain)?.group(1) ?? '');
    final seconds = int.tryParse(RegExp(r'(\d+)초').firstMatch(remain)?.group(1) ?? '') ?? 0;
    return minutes == null ? 86400 : minutes * 60 + seconds;
  }

  String get id => recordId ?? '${station}_$busNum';
}

class BusDataService {
  static List<BusArrivalInfo> getRegisteredBuses() => [];

}

class BusListNotifier extends Notifier<List<BusArrivalInfo>> {
  @override
  List<BusArrivalInfo> build() {
    return BusDataService.getRegisteredBuses();
  }

  void replaceBuses(List<BusArrivalInfo> buses) { state = buses; }

  void addBus(BusArrivalInfo bus) {
    final alreadyExists = state.any((item) => item.id == bus.id);
    if (alreadyExists) return;

    state = [...state, bus];
  }

  void removeBus(BusArrivalInfo bus) {
    state = state.where((item) => item.id != bus.id).toList();
  }

  bool isRegistered(BusArrivalInfo bus) {
    return state.any((item) => item.id == bus.id);
  }
}

final busListProvider =
    NotifierProvider<BusListNotifier, List<BusArrivalInfo>>(BusListNotifier.new);