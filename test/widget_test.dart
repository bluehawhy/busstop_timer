import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:busstop_timer/main.dart';

void main() {
  testWidgets('Bus Timer home opens with the primary navigation', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: BusAlarmApp()));
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('내 버스'), findsOneWidget);
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
  });
}
