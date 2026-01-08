import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Service to handle audio recording and haptic feedback.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _lastRecordingPath;

  /// Starts recording audio and provides haptic feedback.
  Future<void> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        _lastRecordingPath = p.join(directory.path, 'scan_audio.m4a');

        // Feedback: Vibration and Haptic
        if (await Vibration.hasVibrator() ?? false) {
          Vibration.vibrate(duration: 100);
        }
        HapticFeedback.mediumImpact();

        // Start recording
        await _recorder.start(const RecordConfig(), path: _lastRecordingPath!);
      }
    } catch (e) {
      print("Error starting recording: $e");
    }
  }

  /// Stops recording audio and provides haptic feedback.
  Future<File?> stopRecording() async {
    try {
      final path = await _recorder.stop();

      print("Recorded audio path: $path");
      // Feedback: Vibration and Haptic
      if (await Vibration.hasVibrator() ?? false) {
        Vibration.vibrate(duration: 200);
      }
      HapticFeedback.heavyImpact();

      if (path != null) {
        return File(path);
      }
    } catch (e) {
      print("Error stopping recording: $e");
    }
    return null;
  }

  /// Cleans up the recorder.
  void dispose() {
    _recorder.dispose();
  }
}
