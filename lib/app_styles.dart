import 'package:flutter/material.dart';

/// Bus Timer visual system derived from assets/concept.
class AppColors {
  static const Color primary = Color(0xFF08746D);
  static const Color primaryDark = Color(0xFF07524E);
  static const Color accent = Color(0xFFD9F45C);
  static const Color ink = Color(0xFF112B46);
  static const Color secondaryText = Color(0xFF718096);
  static const Color background = Color(0xFFFFFCF6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE8E7E1);
  static const Color success = Color(0xFF279B69);
  static const Color warning = Color(0xFFEAAE31);
  static const Color danger = Color(0xFFD9534F);
  static const Color inactive = Color(0xFF9AA6B2);
  static const Color routeBlue = Color(0xFF2878D7);
  static const Color routeGreen = Color(0xFF38A35A);
}

class AppTextStyles {
  static const TextStyle pageTitle = TextStyle(
    color: AppColors.ink,
    fontSize: 25,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
  );

  static const TextStyle busNumber = TextStyle(
    color: AppColors.ink,
    fontSize: 22,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle stationName = TextStyle(
    color: AppColors.secondaryText,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static TextStyle arrivalTime(Color color) => TextStyle(
        color: color,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      );
}
