import 'package:camera/camera.dart';
import 'dart:async';

/// Service to handle all camera-related operations.
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;

  /// Initializes the camera. Finds the first back camera and starts the preview.
  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        print("No cameras found");
        return;
      }

      // Find the first back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false, // Audio for video is not needed, we use separate recorder
      );

      await _controller!.initialize();
      _isInitialized = true;
    } catch (e) {
      print("Error initializing camera: $e");
      _isInitialized = false;
    }
  }

  /// Captures a photo and returns the XFile.
  Future<XFile?> takePicture() async {
    if (!_isInitialized || _controller == null) {
      print("Camera not initialized");
      return null;
    }

    try {
      return await _controller!.takePicture();
    } catch (e) {
      print("Error taking picture: $e");
      return null;
    }
  }

  /// Starts streaming images from the camera.
  Future<void> startVideoRecording() async {
    if (!_isInitialized || _controller == null) return;
    try {
      await _controller!.startVideoRecording();
    } catch (e) {
      print("Error starting video recording: $e");
    }
  }

  Future<XFile?> stopVideoRecording() async {
    if (!_isInitialized || _controller == null) return null;
    try {
      return await _controller!.stopVideoRecording();
    } catch (e) {
      print("Error stopping video recording: $e");
      return null;
    }
  }

  /// Disposes the camera controller.
  Future<void> dispose() async {
    await _controller?.dispose();
    _isInitialized = false;
  }
}
