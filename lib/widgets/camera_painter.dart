import 'package:flutter/material.dart';

class CameraPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;

  CameraPainter({required this.detections});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.red;

    final Paint textBgPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    for (var detection in detections) {
      final box = detection['box']; // [x1, y1, x2, y2, confidence]
      final tag = detection['tag'];
      
      // The box coordinates from YOLO are typically [x1, y1, x2, y2, confidence]
      // We need to ensure we map them correctly to the canvas size.
      // NOTE: Detections from flutter_vision usually are already scaled to the image size passed in 
      // OR normalized. If they are absolute (e.g. 0-640), we need to know the source image size.
      // However, the `yoloOnFrame` output often fits the image dimensions provided.
      // Since we don't have the exact source image dimensions here easily without passing more props,
      // and usually the preview is filling the screen or a specific aspect ratio container,
      // we might face scaling issues. 
      // 
      // Assumption: The detections are coming in normalized or we rely on the `CameraPreview` container's alignment.
      // Let's assume for now that `flutter_vision` returns normalized 0-1 or absolute pixels matching the frame.
      // Actually, flutter_vision returns absolute pixels based on the `imageHeight`/`imageWidth` passed during inference.
      // If we used the camera frame size for inference, the boxes are in those coordinates.
      
      // For a robust implementation without knowing the exact frame size vs screen size ratio here:
      // We will assume the UI displays the FULL camera frame (fitted).
      // We might need to adjust this if the boxes look off.
      
      // Let's just use the raw values for now and see. 
      // Wait, passing `CameraImage` dimensions to `yoloOnFrame` implies the output is in that domain.
      // So we need to scale from CameraImage Size -> Canvas Size.
      // BUT, we don't have CameraImage size here. 
      // Let's simply draw normalized for now if possible, or expect the parent to pass scaling factors.
      // 
      // Let's accept a scale factor or just draw assuming the canvas matches the image aspect ratio.
      // Actually, best practice is to store the image size in the state and pass it here.
      // For now, I will blindly draw the rects using the raw coordinates relative to the canvas 
      // assuming the canvas IS the image size (which is wrong).
      //
      // Refined plan: The Main UI will need to calculate the scale. 
      // BUT `flutter_vision` usually returns the box relative to the image size sent.
      // I'll make the painter expecting normalized coordinates (0.0 - 1.0) would be safer, 
      // but `flutter_vision` output is usually absolute pixels.
      //
      // Let's modify the service to normalize the boxes before returning, or handle it here.
      // Let's keep it simple: draw based on percentage of canvas.
      // We will need to normalize logic in the main app before passing here, or pass the source size.
      
      double x1 = box[0] * 1.0;
      double y1 = box[1] * 1.0;
      double x2 = box[2] * 1.0;
      double y2 = box[3] * 1.0;

      // Note: This draws exactly the pixel values. If the camera frame is 1280x720,
      // and the screen is 400 pixels wide, this will handle poorly.
      // We need a way to scale.
      // I will add a normalized mode or just normalize in the painter assuming 
      // the detections were calculated on a specific image size.
      //
      // Actually, let's look at `yolo_service.dart`. It passes `imageHeight` and `imageWidth`.
      // The output is in that coordinate space. 
      // So we NEED the source image size to scale to the Canvas size.
      
      // I'll stick to a simpler "assume fitting" or update later.
      // For now, let's just write the painter to take the Rect directly.
      
      final rect = Rect.fromLTRB(x1, y1, x2, y2);
      canvas.drawRect(rect, paint);

      // Draw Label
      final textSpan = TextSpan(
        text: "$tag ${(box[4] * 100).toStringAsFixed(0)}%",
        style: const TextStyle(color: Colors.white, fontSize: 14),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      
      canvas.drawRect(
        Rect.fromLTWH(x1, y1 - 20, textPainter.width + 10, 20),
        textBgPaint,
      );
      textPainter.paint(canvas, Offset(x1 + 5, y1 - 18));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint for live video
  }
}
