// lib/app_styles.dart

import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF2196F3);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color danger = Color(0xFFF44336);
  static const Color inactive = Color(0xFF9E9E9E);
  static const Color background = Color(0xFFF5F5F5);
}

class AppTextStyles {
  static const TextStyle busNumber = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );

  static const TextStyle stationName = TextStyle(
    fontSize: 14,
    color: AppColors.inactive,
  );

  static TextStyle arrivalTime(Color color) => TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color,
      );
}