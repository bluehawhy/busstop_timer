// lib/bus_data_service.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

class BusArrivalInfo {
  final String station;
  final String busNum;
  final String remain;
  final String? nextBus;

  const BusArrivalInfo({
    required this.station,
    required this.busNum,
    required this.remain,
    this.nextBus,
  });

  String get id => '${station}_$busNum';
}

class BusDataService {
  // 나중에 여기서 공공데이터 API를 호출하게 됩니다.
  static List<BusArrivalInfo> getRegisteredBuses() {
    return const [
      BusArrivalInfo(
        station: "부산역 (중앙대로)",
        busNum: "179",
        remain: "5분 30초",
        nextBus: "12분",
      ),
      BusArrivalInfo(
        station: "서면역",
        busNum: "1000",
        remain: "3분",
        nextBus: null,
      ),
    ];
  }
}

class BusListNotifier extends Notifier<List<BusArrivalInfo>> {
  @override
  List<BusArrivalInfo> build() {
    return BusDataService.getRegisteredBuses();
  }

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