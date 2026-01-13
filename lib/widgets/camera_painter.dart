import 'package:flutter/material.dart';

class CameraPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final Size imageSize;
  final int sensorOrientation;

  CameraPainter({
    required this.detections, 
    required this.imageSize,
    required this.sensorOrientation,
  });

  // Color map for different object classes to match user's example
  Color _getColor(String label) {
    switch (label.toLowerCase()) {
      case 'person': return Colors.red;
      case 'bus': return Colors.greenAccent;
      case 'car': return Colors.blueAccent;
      case 'bottle': return Colors.orangeAccent;
      case 'chair': return Colors.purpleAccent;
      case 'cell phone': return Colors.yellowAccent;
      default: return Colors.redAccent;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (imageSize.width == 0 || imageSize.height == 0) return;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (var detection in detections) {
      final box = detection['box']; // [x1, y1, x2, y2, confidence]
      final tag = detection['tag'].toString();
      final confidence = box[4] as double;

      double x1, y1, x2, y2;

      // Normalize raw frame coordinates (sensor-relative)
      // Note: yoloOnFrame returns absolute pixels based on the dimensions we passed
      double nx1 = box[0] / imageSize.width;
      double ny1 = box[1] / imageSize.height;
      double nx2 = box[2] / imageSize.width;
      double ny2 = box[3] / imageSize.height;

      // Transform normalized coordinates based on sensor orientation
      // For most Android devices, sensorOrientation is 90.
      if (sensorOrientation == 90) {
        // 90 deg Clockwise rotation
        x1 = (1.0 - ny2) * size.width;
        x2 = (1.0 - ny1) * size.width;
        y1 = nx1 * size.height;
        y2 = nx2 * size.height;
      } else if (sensorOrientation == 270) {
        // 270 deg Clockwise (90 deg Counter-Clockwise)
        x1 = ny1 * size.width;
        x2 = ny2 * size.width;
        y1 = (1.0 - nx2) * size.height;
        y2 = (1.0 - nx1) * size.height;
      } else {
        // 0 or 180 (Simple scaling)
        x1 = nx1 * size.width;
        x2 = nx2 * size.width;
        y1 = ny1 * size.height;
        y2 = ny2 * size.height;
      }

      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      final color = _getColor(tag);
      paint.color = color;
      
      // Draw Bounding Box
      canvas.drawRect(rect, paint);

      // Prepare Label
      final textSpan = TextSpan(
        text: "$tag ${(confidence * 100).toStringAsFixed(0)}%",
        style: const TextStyle(
          color: Colors.white, 
          fontSize: 14, 
          fontWeight: FontWeight.bold
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      
      // Draw Label Background (matching the reference image style)
      final labelBgRect = Rect.fromLTWH(
        x1 - 1.5, 
        y1 - textPainter.height - 4, 
        textPainter.width + 10, 
        textPainter.height + 4
      );
      
      canvas.drawRect(labelBgRect, Paint()..color = color);
      textPainter.paint(canvas, Offset(x1 + 3.5, y1 - textPainter.height - 2));
    }

    // DRAW DIAGNOSTIC INFO (Temporary for debugging)
    if (detections.isNotEmpty) {
      final diagSpan = TextSpan(
        text: "Sensor: $sensorOrientation | Img: ${imageSize.width.toInt()}x${imageSize.height.toInt()} | Canvas: ${size.width.toInt()}x${size.height.toInt()}",
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10),
      );
      final diagPainter = TextPainter(text: diagSpan, textDirection: TextDirection.ltr);
      diagPainter.layout();
      diagPainter.paint(canvas, Offset(10, size.height - 20));
    }
  }

  @override
  bool shouldRepaint(covariant CameraPainter oldDelegate) {
    return true;
  }
}
