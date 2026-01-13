import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionPainter extends CustomPainter {
  final List<DetectedFaceInfo> detectedFaces;
  final Size imageSize;

  FaceDetectionPainter({
    required this.detectedFaces,
    required this.imageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint recognizedPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final Paint unknownPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (var faceInfo in detectedFaces) {
      final boundingBox = faceInfo.boundingBox;
      
      // Scale bounding box to screen size
      final rect = Rect.fromLTRB(
        boundingBox.left * scaleX,
        boundingBox.top * scaleY,
        boundingBox.right * scaleX,
        boundingBox.bottom * scaleY,
      );

      // Draw box
      canvas.drawRect(
        rect,
        faceInfo.isRecognized ? recognizedPaint : unknownPaint,
      );

      // Draw label if recognized
      if (faceInfo.isRecognized && faceInfo.label != null) {
        final textSpan = TextSpan(
          text: faceInfo.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.green,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();

        // Position label above bounding box
        final offset = Offset(
          rect.left,
          rect.top - textPainter.height - 5,
        );

        textPainter.paint(canvas, offset);
      }
    }
  }

  @override
  bool shouldRepaint(FaceDetectionPainter oldDelegate) {
    return oldDelegate.detectedFaces != detectedFaces;
  }
}

class DetectedFaceInfo {
  final Rect boundingBox;
  final bool isRecognized;
  final String? label; // "Name, Relationship"

  DetectedFaceInfo({
    required this.boundingBox,
    required this.isRecognized,
    this.label,
  });
}
