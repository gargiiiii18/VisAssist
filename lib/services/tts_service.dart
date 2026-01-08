import 'package:flutter_tts/flutter_tts.dart';

/// Service to handle Text-to-Speech operations.
class TTSService {
  final FlutterTts _flutterTts = FlutterTts();

  /// Initializes the TTS engine with default settings.
  Future<void> initialize() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0); // Set to maximum volume
    await _flutterTts.setPitch(1.0);
  }

  /// Speaks the given text at maximum volume.
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    
    // Ensure volume is at maximum before speaking
    await _flutterTts.setVolume(1.0);
    await _flutterTts.speak(text);
  }

  /// Stops any ongoing speech.
  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
