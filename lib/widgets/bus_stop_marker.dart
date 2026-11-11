import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Creates the same rounded bus pictogram on Flutter Web, Android and iOS.
/// MapLibre consumes the PNG bytes; no font-dependent map sprite is required.
Future<Uint8List> createBusStopMarker({required bool selected}) async {
  const dimension = 64;
  const center = Offset(32, 32);
  final background = selected
      ? const Color(0xFFF36A2B)
      : const Color(0xFF008678);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // The thick white edge separates the symbol from streets and route lines.
  canvas.drawCircle(center, 30, Paint()..color = Colors.white);
  canvas.drawCircle(center, 26, Paint()..color = background);
  final busBody = RRect.fromRectAndRadius(
    const Rect.fromLTWH(18, 17, 28, 30),
    const Radius.circular(5),
  );
  canvas.drawRRect(busBody, Paint()..color = Colors.white);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(22, 21, 20, 13),
      const Radius.circular(2),
    ),
    Paint()..color = background,
  );
  canvas.drawCircle(const Offset(24, 40), 2.3, Paint()..color = background);
  canvas.drawCircle(const Offset(40, 40), 2.3, Paint()..color = background);
  for (final x in [22.0, 39.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 46, 4, 4),
        const Radius.circular(1),
      ),
      Paint()..color = Colors.white,
    );
  }

  final image = await recorder.endRecording().toImage(dimension, dimension);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    throw StateError('Unable to draw a stop marker');
  }
  return data.buffer.asUint8List();
}
