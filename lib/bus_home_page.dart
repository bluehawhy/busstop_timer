// lib/bus_home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bus_data_service.dart';
import 'app_styles.dart';

// --- 1. 메인 페이지 (즐겨찾기 목록) ---
class BusHomePage extends ConsumerWidget {
  const BusHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busList = ref.watch(busListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "내 버스 알람",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.add_location_alt, color: AppColors.primary),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddBusPage()),
            );
          },
        ),
      ),
      body: busList.isEmpty
          ? const Center(
              child: Text("등록된 버스가 없습니다.\n좌측 상단 아이콘을 눌러 추가하세요."),
            )
          : ListView.builder(
              itemCount: busList.length,
              itemBuilder: (context, index) {
                final bus = busList[index];
                return _buildMainBusCard(context, ref, bus);
              },
            ),
    );
  }

  // 메인 화면의 카드 UI (스와이프 삭제 기능 포함)
  Widget _buildMainBusCard(
    BuildContext context,
    WidgetRef ref,
    BusArrivalInfo bus,
  ) {
    return Dismissible(
      key: Key(bus.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        ref.read(busListProvider.notifier).removeBus(bus);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${bus.busNum}번 버스를 삭제했습니다."),
          ),
        );
      },
      child: Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(15),
          title: Text(bus.station, style: AppTextStyles.stationName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${bus.busNum}번", style: AppTextStyles.busNumber),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _infoChip("이번: ${bus.remain}", AppColors.primary),
                  _infoChip(
                    "다음: ${bus.nextBus ?? '정보 없음'}",
                    bus.nextBus == null
                        ? AppColors.inactive
                        : AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
          trailing: const Icon(Icons.star, color: Colors.amber),
        ),
      ),
    );
  }

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(text, style: AppTextStyles.arrivalTime(color)),
    );
  }
}

// --- 2. 추가 페이지 (정류장 검색 및 확장형 리스트) ---
class AddBusPage extends ConsumerStatefulWidget {
  const AddBusPage({super.key});

  @override
  ConsumerState<AddBusPage> createState() => _AddBusPageState();
}

class _AddBusPageState extends ConsumerState<AddBusPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  // 샘플 정류장 데이터
  final List<Map<String, dynamic>> _nearbyStations = [
    {"name": "부산역 (중앙대로)", "distance": "85m", "id": "01001"},
    {"name": "초량역 1번 출구", "distance": "120m", "id": "01002"},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredStations {
    if (_searchKeyword.trim().isEmpty) {
      return _nearbyStations;
    }

    return _nearbyStations.where((station) {
      final name = station['name'].toString().toLowerCase();
      final id = station['id'].toString().toLowerCase();
      final keyword = _searchKeyword.toLowerCase();

      return name.contains(keyword) || id.contains(keyword);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final registeredBuses = ref.watch(busListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("정류장 추가"),
      ),
      body: Column(
        children: [
          // 검색바
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchKeyword = value;
                });
              },
              decoration: InputDecoration(
                hintText: "정류장 이름 또는 ID 검색",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.withValues(alpha: 0.1),
              ),
            ),
          ),
          // 내 주변 타이틀
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: const [
                Icon(Icons.my_location, size: 18, color: AppColors.primary),
                SizedBox(width: 8),
                Text(
                  "내 주변 정류장 (100m 이내)",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // 확장형 정류장 리스트
          Expanded(
            child: ListView.builder(
              itemCount: _filteredStations.length,
              itemBuilder: (context, index) {
                final station = _filteredStations[index];

                // 정류장별 가짜 버스 데이터
                final List<BusArrivalInfo> busList = [
                  BusArrivalInfo(
                    station: station['name'],
                    busNum: "1001",
                    remain: "5분",
                    nextBus: "15분",
                  ),
                  BusArrivalInfo(
                    station: station['name'],
                    busNum: "1002",
                    remain: "곧 도착",
                    nextBus: "10분",
                  ),
                ];

                return Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    leading: const Icon(Icons.location_on, color: AppColors.primary),
                    title: Text(
                      station['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "ID: ${station['id']} | ${station['distance']}",
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    // 정류장 클릭 시 펼쳐지는 버스 목록
                    children: busList.map((bus) {
                      final isFavorite = registeredBuses.any(
                        (item) => item.id == bus.id,
                      );

                      return Container(
                        padding: const EdgeInsets.only(left: 16, right: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: Colors.grey.withValues(alpha: 0.1),
                            ),
                          ),
                          color: Colors.grey.withValues(alpha: 0.02),
                        ),
                        child: ListTile(
                          title: Text(
                            "${bus.busNum}번",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Row(
                            children: [
                              Text(
                                "이번: ${bus.remain}",
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                "다음: ${bus.nextBus ?? '정보 없음'}",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              color: isFavorite ? Colors.amber : Colors.grey,
                            ),
                            onPressed: () {
                              if (isFavorite) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("${bus.busNum}번은 이미 등록되어 있습니다."),
                                  ),
                                );
                                return;
                              }

                              ref.read(busListProvider.notifier).addBus(bus);

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("${bus.busNum}번 버스를 등록했습니다."),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}