import 'package:maplibre_gl/maplibre_gl.dart';

/// Busan district choices. Coordinates are navigation anchors near each
/// district office, not surveyed district boundaries or reverse-geocoding.
class BusanMapRegion {
  const BusanMapRegion(this.district, this.latitude, this.longitude);

  final String district;
  final double latitude;
  final double longitude;

  String get label => '부산광역시 $district';
  LatLng get center => LatLng(latitude, longitude);
}

const busanMapRegions = <BusanMapRegion>[
  BusanMapRegion('중구', 35.106, 129.033),
  BusanMapRegion('서구', 35.097, 129.023),
  BusanMapRegion('동구', 35.129, 129.045),
  BusanMapRegion('영도구', 35.091, 129.069),
  BusanMapRegion('부산진구', 35.162, 129.053),
  BusanMapRegion('동래구', 35.205, 129.083),
  BusanMapRegion('남구', 35.136, 129.086),
  BusanMapRegion('북구', 35.197, 129.033),
  BusanMapRegion('해운대구', 35.163, 129.163),
  BusanMapRegion('사하구', 35.105, 128.974),
  BusanMapRegion('금정구', 35.242, 129.092),
  BusanMapRegion('강서구', 35.213, 128.980),
  BusanMapRegion('연제구', 35.1796, 129.0756),
  BusanMapRegion('수영구', 35.145, 129.114),
  BusanMapRegion('사상구', 35.153, 128.991),
  BusanMapRegion('기장군', 35.245, 129.215),
];

const initialBusanMapRegion =
    BusanMapRegion('연제구', 35.1796, 129.0756);
