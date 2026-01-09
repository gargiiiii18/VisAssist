import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';

class VoiceControlService {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _isAttemptingToListen = false;
  Function? _onStartCommand;
  Timer? _restartTimer;

  Future<bool> initialize(Function onStartCommand) async {
    _onStartCommand = onStartCommand;
    try {
      bool available = await _speechToText.initialize(
        onError: (val) {
          // print('Speech Error: ${val.errorMsg}');
          _isAttemptingToListen = false;
          _handleRestart();
        },
        onStatus: (val) {
          // print('Speech Status: $val');
          if (val == 'notListening' || val == 'done') {
            _isAttemptingToListen = false;
            _handleRestart();
          }
        },
      );
      // print("Speech recognition available: $available");
      return available;
    } catch (e) {
      // print("Speech initialize exception: $e");
      return false;
    }
  }

  void _handleRestart() {
    if (!_isListening) return;

    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 800), () {
      if (_isListening && !_speechToText.isListening && !_isAttemptingToListen) {
        _startInternal();
      }
    });
  }

  Future<void> startListening() async {
    _isListening = true;
    _restartTimer?.cancel();
    if (!_speechToText.isListening && !_isAttemptingToListen) {
      await _startInternal();
    }
  }

  Future<void> _startInternal() async {
    if (!_isListening || _isAttemptingToListen) return;
    
    _isAttemptingToListen = true;
    // print(">>> [Microphone] Activating - Listening for 'START'...");
    
    try {
      await _speechToText.cancel();
      
      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 10),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.search, // Better for short commands
      );
      // print(">>> [Microphone] Listening session active.");
    } catch (e) {
      _isAttemptingToListen = false;
      // print("Listen exception: $e");
      _handleRestart();
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!_isListening) return;

    String words = result.recognizedWords.toLowerCase().trim();
    if (words.isNotEmpty) {
      // print("HEARD: '$words' (Final: ${result.finalResult})");
    }
    
    // Check for "start" anywhere in the phrase to be more sensitive
    if (words.contains("start")) {
      // print("!!! [SUCCESS] Found 'START' command !!!");
      Vibration.vibrate(duration: 300); // Longer vibration for clear feedback
      
      _isListening = false;
      _speechToText.stop();
      _restartTimer?.cancel();
      
      if (_onStartCommand != null) {
        _onStartCommand!();
      }
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    _isAttemptingToListen = false;
    _restartTimer?.cancel();
    await _speechToText.stop();
    await _speechToText.cancel();
  }

  /// Listens for a single user query and returns the text.
  Future<String?> listenForQuery() async {
    Completer<String?> completer = Completer();
    
    // Stop any ongoing listen
    await stopListening();

    try {
      if (!await _speechToText.initialize()) {
        return null; // Speech not available
      }

      await _speechToText.listen(
        onResult: (result) {
          if (result.finalResult) {
            completer.complete(result.recognizedWords);
            _speechToText.stop();
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      );
      
      // Fallback timer if no final result comes quickly
      // (speech_to_text sometimes doesn't fire finalResult if silence follows immediately)
      // This is basic handling; for production might need more robust silence detection.
    } catch (e) {
      print("Error listening for query: $e");
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }
}
