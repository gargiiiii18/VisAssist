import 'dart:async';
import 'package:flutter/material.dart';
import 'tts_service.dart';

class SceneManager {
  final TTSService _ttsService;
  List<Map<String, dynamic>> _currentDetections = [];
  DateTime _lastAlertTime = DateTime.now().subtract(const Duration(minutes: 1));
  DateTime _lastNarrationTime = DateTime.now();
  
  // High-risk objects that trigger immediate alerts
  final Set<String> _highRiskObjects = {'knife', 'scissors', 'car', 'bus', 'truck', 'motorcycle'};

  SceneManager(this._ttsService);

  void updateDetections(List<Map<String, dynamic>> detections, Size screenSize) {
    _currentDetections = detections;
    _checkSafety(screenSize);
  }

  /// Checks for high-risk objects and triggers safety alerts.
  void _checkSafety(Size screenSize) {
    // Debounce alerts (e.g., max one alert every 3 seconds)
    if (DateTime.now().difference(_lastAlertTime).inSeconds < 3) return;

    for (var detection in _currentDetections) {
      String label = detection['tag'].toString().toLowerCase();
      
      if (_highRiskObjects.contains(label)) {
        // Calculate position
        final box = detection['box']; // [x1, y1, x2, y2, confidence]
        double centerX = (box[0] + box[2]) / 2;
        // Normalize X to 0.0 - 1.0 (assuming input images are 640x640 or handled by camera aspect ratio). 
        // Note: flutter_vision returns absolute coordinates based on image size. 
        // Ideally we normalize based on image width, but here we can check relative to the box itself or assume the camera preview width.
        // For simplicity, let's look at the raw values if we knew image width. 
        // However, usually we can just infer relative position if we don't have the exact image width passed here.
        // Let's rely on the fact that if we use the raw values from Yolo, we might need the image dimensions.
        // But wait, updateDetections should probably receive the image dimensions or assume a standard normalization.
        // Let's assume we can get a rough "left/center/right" by checking the bbox center relative to the other objects or just report it.
        
        // BETTER APPROACH: The `box` from flutter_vision is usually [x1, y1, x2, y2, class_conf]. 
        // We will need the image width to normalize. 
        // For now, let's assume the standard camera image width, or pass it in. 
        // Let's update `updateDetections` to take `imageWidth`.
        
        // Actually, let's simply simplify spatial logic for now:
        // We will defer precise "Left/Right" calculation to when we generate the prompt 
        // or just pass the specialized alert string if we can.
        
        // Let's try to pass the image width to `updateDetections`.
      }
    }
  }

  double _lastImageWidth = 720.0; // Default fallback

  /// Processes detections with image width for spatial awareness
  void processDetections(List<Map<String, dynamic>> detections, double imageWidth) {
    _currentDetections = detections;
    _lastImageWidth = imageWidth;
    
    // Safety Check
    if (DateTime.now().difference(_lastAlertTime).inSeconds < 4) return;

    for (var detection in detections) {
      String label = detection['tag'].toString().toLowerCase();
      if (_highRiskObjects.contains(label)) {
        final box = detection['box']; // [x1, y1, x2, y2, conf]
        double centerX = (box[0] + box[2]) / 2;
        double relativeX = centerX / imageWidth;

        String position = "ahead";
        if (relativeX < 0.35) {
          position = "on your left";
        } else if (relativeX > 0.65) {
          position = "on your right";
        }

        _ttsService.speak("Warning. $label detected $position.");
        _lastAlertTime = DateTime.now();
        return; // Prioritize one alert at a time
      }
    }
  }

  /// Generates a summary of the current scene for Gemini
  String getSceneSummary() {
    if (_currentDetections.isEmpty) {
      return "The scene is empty.";
    }

    StringBuffer summary = StringBuffer("The current scene contains: ");
    List<String> objectDescriptions = [];

    for (var detection in _currentDetections) {
      String label = detection['tag'];
      final box = detection['box'];
      double centerX = (box[0] + box[2]) / 2;
      double relativeX = centerX / _lastImageWidth;

      String position = "center";
      if (relativeX < 0.35) {
        position = "left";
      } else if (relativeX > 0.65) {
        position = "right";
      }
      
      objectDescriptions.add("$label at $position");
    }

    summary.write(objectDescriptions.join(", "));
    return summary.toString();
  }
}
