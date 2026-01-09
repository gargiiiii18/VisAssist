import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'services/camera_service.dart';
import 'services/tts_service.dart';
import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'services/logging_service.dart';
import 'services/voice_control_service.dart';
import 'services/store_service.dart';

enum AppMode { idle, vision, navigation }


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggingService().initialize(); // Initialize logging early
  runApp(const VisionApp());
}

class VisionApp extends StatelessWidget {
  const VisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vision Assistant',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),
      home: const VisionHomePage(),
    );
  }
}

class VisionHomePage extends StatefulWidget {
  const VisionHomePage({super.key});

  @override
  State<VisionHomePage> createState() => _VisionHomePageState();
}

class _VisionHomePageState extends State<VisionHomePage> with WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final TTSService _ttsService = TTSService();
  final ApiService _apiService = ApiService();
  final LoggingService _loggingService = LoggingService();
  final VoiceControlService _voiceService = VoiceControlService();
  final AudioService _audioService = AudioService();
  final StoreService _storeService = StoreService();


  bool _isProcessing = false;
  String _statusText = "Ready to Scan";
  int _countdown = 10;
  AppMode _currentMode = AppMode.idle;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      // Don't initialize camera yet - wait for Vision Scan
      await _ttsService.initialize();
      await _loggingService.initialize();
      
      bool speechAvailable = await _voiceService.initialize(() {
        if (!_isProcessing) {
          _analyzeVideoFlow();
        }
      });

      if (speechAvailable) {
        _voiceService.startListening();
        if (mounted) {
          setState(() {
            _statusText = "Listening for 'START'...";
          });
        }
        _ttsService.speak("App ready. Say START to begin.");
      } else {
        if (mounted) {
          setState(() {
            _statusText = "Voice trigger unavailable";
          });
        }
        _ttsService.speak("Voice trigger is unavailable. Please use the on-screen button.");
      }
    } else {
      setState(() => _statusText = "Permissions denied");
    }
  }

  Future<void> _ensureCameraOn() async {
    if (!_isCameraInitialized) {
      setState(() => _statusText = "Starting Camera...");
      await _cameraService.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _statusText = "Camera Ready";
        });
      }
    }
  }

  Future<void> _ensureCameraOff() async {
    if (_isCameraInitialized) {
      await _cameraService.dispose();
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _statusText = "Camera Off";
        });
      }
    }
  }

  Future<void> _analyzeVideoFlow() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _currentMode = AppMode.vision;
      _countdown = 10;
    });

    try {
      await _voiceService.stopListening();
      
      // Ensure camera is active for Vision Scan
      await _ensureCameraOn();
      
      // Delay to allow microphone/hardware to release from voice service
      await Future.delayed(const Duration(milliseconds: 1000));
      
      if (!mounted) return;
      
      await _cameraService.startVideoRecording();
      await _audioService.startRecording();
      _ttsService.speak("Recording started. Please move the camera and ask your question.");

      // 10 Second Countdown
      for (int i = 10; i > 0; i--) {
        if (!mounted) return;
        
        // WATCHDOG: Check if recording is still active
        if (_cameraService.controller == null || !_cameraService.controller!.value.isRecordingVideo) {
          throw Exception("Recording stopped unexpectedly.");
        }

        setState(() {
          _statusText = "Recording: $i seconds left";
          _countdown = i;
        });
        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() => _statusText = "Processing scan...");
      final XFile? videoFile = await _cameraService.stopVideoRecording();
      File? audioQueryFile = await _audioService.stopRecording();
      
      // Filter out 'empty' or extremely silent audio files (less than 10KB)
      if (audioQueryFile != null && await audioQueryFile.exists()) {
        final int fileSize = await audioQueryFile.length();
        if (fileSize < 10000) { // 10KB threshold
          print("Audio query too small ($fileSize bytes). Filtering as empty.");
          audioQueryFile = null;
        }
      }
      
      if (videoFile != null) {
        final result = await _apiService.analyzeVideo(
          videoFile: File(videoFile.path),
          audioFile: audioQueryFile,
        );
        
        // Log to file
        await _loggingService.logDetectedItems(result);
        
        // Update UI and Speak
        setState(() {
          _statusText = "Found: $result";
          _isProcessing = false;
        });
        await _ttsService.speak("Found: $result");
        _voiceService.startListening();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = "Error: $e";
      });
      _ttsService.speak("An error occurred during scanning.");
      _voiceService.startListening();
    }
  }

  Future<void> _analyzeNavigationFlow() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _currentMode = AppMode.navigation;
      _statusText = "Initializing Navigation...";
    });

    try {
      await _voiceService.stopListening();
      
      // Turn off camera for Navigation
      await _ensureCameraOff();
      
      // Prompt user
      await _ttsService.speak("What are you looking for?");
      
      // Handover delay
      await Future.delayed(const Duration(milliseconds: 1500));
      
      if (!mounted) return;
      
      // Record for 5 seconds
      await _audioService.startRecording();
      
      for (int i = 5; i > 0; i--) {
        if (!mounted) return;
        setState(() {
          _statusText = "Listening: $i...";
          _countdown = i;
        });
        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() => _statusText = "Locating item...");
      final File? audioFile = await _audioService.stopRecording();
      
      if (audioFile != null) {
        final String context = _storeService.getMapContext();
        final result = await _apiService.analyzeNavigationQuery(
          audioFile: audioFile,
          storeMapContext: context,
        );
        
        setState(() {
          _statusText = result;
          _isProcessing = false;
        });
        await _ttsService.speak(result);
        _voiceService.startListening();
      } else {
        throw Exception("No audio captured.");
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusText = "Nav Error: $e";
      });
      _ttsService.speak("Navigation failed. Please try again.");
      _voiceService.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Conditional Camera Preview
          Positioned.fill(
            child: (_isCameraInitialized && _cameraService.controller != null && _cameraService.controller!.value.isInitialized)
                ? CameraPreview(_cameraService.controller!)
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _currentMode == AppMode.navigation ? Icons.map : Icons.videocam_off,
                            size: 80,
                            color: Colors.white24,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _currentMode == AppMode.navigation ? "NAVIGATION MODE" : "CAMERA INACTIVE",
                            style: const TextStyle(color: Colors.white38, letterSpacing: 2),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Status Overlay
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blueAccent, width: 2),
              ),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Action Buttons
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Vision Scan Button
                  SizedBox(
                    width: size.width * 0.85,
                    height: 100,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isProcessing ? Colors.grey : Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 10,
                      ),
                      onPressed: _isProcessing ? null : _analyzeVideoFlow,
                      child: _isProcessing
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "VISION SCAN",
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Navigation Button
                  SizedBox(
                    width: size.width * 0.85,
                    height: 100,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isProcessing ? Colors.grey : Colors.orangeAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 10,
                      ),
                      onPressed: _isProcessing ? null : _analyzeNavigationFlow,
                      child: _isProcessing
                          ? const Text("PROCESSING...")
                          : const Text(
                              "STORES NAVIGATION",
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
