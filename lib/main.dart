// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'bus_home_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: BusAlarmApp(),
    ),
  );
}

class BusAlarmApp extends StatelessWidget {
  const BusAlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus Alarm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const BusHomePage(),
    );
  }
}