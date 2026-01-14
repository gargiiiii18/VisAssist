import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';

class VoiceControlService {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _isInitialized = false;
  
  // Dynamic callbacks
  Function(String)? _statusListener;
  Function(SpeechRecognitionResult)? _resultListener;

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speechToText.initialize(
        onError: (val) {
          print('Speech Error: ${val.errorMsg}');
          _statusListener?.call('error'); // Map error to status flow
        },
        onStatus: (val) {
          print('Speech Status: $val');
          _statusListener?.call(val);
        },
      );
      return _isInitialized;
    } catch (e) {
      print("Speech initialize exception: $e");
      return false;
    }
  }

  Future<void> stopListening() async {
    _isListening = false;
    await _speechToText.stop();
    // Do not cancel instance, just stop listening
  }

  /// Listens for a single user query and returns the text.
  Future<String?> listenForQuery() async {
    Completer<String?> completer = Completer();
    if (!_isInitialized) await initialize();
    
    // Use cancel to immediately clear previous session
    if (_speechToText.isListening) await _speechToText.cancel();

    String lastWords = "";

    _statusListener = (status) {
       if ((status == 'done' || status == 'notListening') && !completer.isCompleted) {
         if (lastWords.isNotEmpty) {
           completer.complete(lastWords);
         } else {
           completer.complete(null);
         }
       }
    };

    try {
      await _speechToText.listen(
        onResult: (result) {
          lastWords = result.recognizedWords;
          if (result.finalResult && !completer.isCompleted) {
            completer.complete(result.recognizedWords);
          }
        },
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      );
    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  /// Listens continuously for specific keywords for a set duration.
  /// Returns the keyword found, or null if timeout/silence.
  Future<String?> listenForKeywords(List<String> keywords, Duration duration) async {
    Completer<String?> completer = Completer();
    
    // Ensure initialized
    if (!_isInitialized) {
      bool success = await initialize();
      if (!success) return null;
    }

    // Use cancel for faster restart
    if (_speechToText.isListening) {
      await _speechToText.cancel();
    }

    // Set up dynamic listeners for this session
    _statusListener = (status) {
      // If complete (done/notListening) and not yet found a keyword
      if ((status == 'done' || status == 'notListening' || status == 'error') && !completer.isCompleted) {
         // Tiny delay to ensure no final result is pending processing
         Future.delayed(const Duration(milliseconds: 100), () {
            if (!completer.isCompleted) completer.complete(null);
         });
      }
    };
    
    // Start Listening
    try {
      await _speechToText.listen(
        onResult: (result) {
          String words = result.recognizedWords.toLowerCase();
          for (var keyword in keywords) {
            if (words.contains(keyword.toLowerCase())) {
               if (!completer.isCompleted) {
                 completer.complete(keyword);
                 // Stop purely to finalize this successful hit
                 _speechToText.stop();
               }
               return;
            }
          }
        },
        listenFor: duration, 
        pauseFor: const Duration(seconds: 10), // Try to keep alive
        cancelOnError: true,
        partialResults: true,
        listenMode: ListenMode.dictation,
      );
      
      _isListening = true;

      // Fail-safe timeout
      // If the engine hangs or doesn't report status, force complete
      Future.delayed(duration + const Duration(seconds: 2), () {
         if (!completer.isCompleted) {
           completer.complete(null);
           _speechToText.stop();
         }
      });

    } catch (e) {
      print("Error listening for keywords: $e");
      if (!completer.isCompleted) completer.complete(null);
    }
    
    return completer.future;
  }
}
