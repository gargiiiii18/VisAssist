import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  File? _logFile;

  Future<void> initialize() async {
    Directory? outputDir;
    try {
      if (Platform.isWindows) {
        // If running as a Windows app, we might be able to write to current dir
        outputDir = Directory('output');
        if (!await outputDir.exists()) {
          await outputDir.create(recursive: true);
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        outputDir = Directory('${directory.path}/output');
        if (!await outputDir.exists()) {
          await outputDir.create(recursive: true);
        }
      }
    } catch (e) {
      // Fallback
      final directory = await getApplicationDocumentsDirectory();
      outputDir = Directory('${directory.path}/output');
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }
    }

    _logFile = File('${outputDir!.path}/log.txt');
    
    print("--------------------------------------------------");
    print("DETECTION LOG FILE: ${_logFile!.path}");
    print("--------------------------------------------------");
  }

  Future<void> logDetectedItems(String items) async {
    if (_logFile == null) await initialize();
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    final message = "[$timestamp] Objects Seen: $items";
    try {
      await _logFile!.writeAsString('$message\n', mode: FileMode.append);
      print("--------------------------------------------------");
      print("LOGGED TO FILE: $message");
      print("--------------------------------------------------");
    } catch (e) {
      print("Logging error: $e");
    }
  }

  Future<String> getLogs() async {
    if (_logFile == null) return "No logs available.";
    if (!await _logFile!.exists()) return "Log file does not exist.";
    return await _logFile!.readAsString();
  }

  Future<void> clearLogs() async {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
    }
  }
}
