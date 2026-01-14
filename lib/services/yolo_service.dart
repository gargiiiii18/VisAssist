import 'dart:math';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:camera/camera.dart';

class YoloService {

  late FlutterVision _vision;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  Future<void> initialize() async {
    _vision = FlutterVision();
    try {
      await _vision.loadYoloModel(
        labels: 'assets/models/labels.txt',
        modelPath: 'assets/models/yolov8n_float16.tflite',
        modelVersion: "yolov8",
        numThreads: 1, // Optimize for device capability
        useGpu: true,
      );
      _isLoaded = true;
    } catch (e) {
      // print("Error loading YOLO model: $e");
    }
  }

  Future<List<Map<String, dynamic>>> runInference(CameraImage cameraImage) async {
    if (!_isLoaded) return [];

    try {
      final result = await _vision.yoloOnFrame(
        bytesList: cameraImage.planes.map((plane) => plane.bytes).toList(),
        imageHeight: cameraImage.height,
        imageWidth: cameraImage.width,
        iouThreshold: 0.4,
        confThreshold: 0.4,
        classThreshold: 0.5,
      );
      return result;
    } catch (e) {
      // print("Error running inference: $e");
      return [];
    }
  }

  Future<void> dispose() async {
    await _vision.closeYoloModel();
    _isLoaded = false;
  }
}
