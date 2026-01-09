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
import 'services/yolo_service.dart';
import 'services/scene_manager.dart';
import 'widgets/camera_painter.dart';


import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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
  
  // New Services
  final YoloService _yoloService = YoloService();
  late SceneManager _sceneManager;

  bool _isProcessingFrame = false;
  List<Map<String, dynamic>> _detections = [];
  String _statusText = "Initializing...";
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sceneManager = SceneManager(_ttsService);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraService.stopImageStream();
    _cameraService.dispose();
    _yoloService.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      
      await _loggingService.initialize();
      await _ttsService.initialize();
      await _cameraService.initialize();
      await _yoloService.initialize();

      if (_yoloService.isLoaded && _cameraService.isInitialized) {
        setState(() => _statusText = "Starting Vision...");
        _startLiveFeed();
      } else {
        setState(() => _statusText = "Initialization Failed");
      }
    } else {
      setState(() => _statusText = "Permissions denied");
    }
  }

  void _startLiveFeed() {
    _cameraService.startImageStream((CameraImage image) async {
      if (_isProcessingFrame) return;

      _isProcessingFrame = true;
      try {
        final detections = await _yoloService.runInference(image);
        
        // Use the image width from the camera image for spatial calculations
        // Note: CameraImage width usually reflects the buffer width (e.g. 720 or 1280 depending on orientation)
        _sceneManager.processDetections(detections, image.width.toDouble());

        if (mounted) {
          setState(() {
            _detections = detections;
            // Update status text with main objects if not listening
            if (!_isListening && detections.isNotEmpty) {
               final labels = detections.map((d) => d['tag']).toSet().join(", ");
               _statusText = "Seeing: $labels";
            } else if (!_isListening) {
               _statusText = "Scanning...";
            }
          });
        }
      } catch (e) {
        // print("Frame processing error: $e");
      } finally {
        _isProcessingFrame = false;
      }
    });
  }

  Future<void> _handleUserQuery() async {
    // Pause inference or ignore alerts while listening?
    // Better to just listen.
    setState(() {
      _isListening = true;
      _statusText = "Listening for query...";
    });
    
    // Haptic feedback
    // await Vibration.vibrate(duration: 100); 

    await _cameraService.stopImageStream(); // Pause vision to save resource/noise

    String? query = await _voiceService.listenForQuery();
    
    if (query != null && query.isNotEmpty) {
      setState(() => _statusText = "Thinking...");
      
      // Get latest scene state from SceneManager logic or better yet, 
      // since we stopped stream, we use the last known state.
      // Ideally we should have kept the stream running to get the 'latest' frame context 
      // BUT for simplicity and resource safety, using the last state is okay for "what is in front of me".
      // Actually, if we stopped stream, `_detections` holds the last frame's data.
      // However, `SceneManager` handles the high-level logic.
      // We'll trust the tracking in SceneManager or just re-construct from `_detections`.
      
      // To ensure we have good context, let's presume the user is pointing at what they want to know about.
      // We pass the image width used in last inference?
      // Let's assume a default or store it.
      // SceneManager keeps track? No, currently it processes instantly.
      // We should probably rely on `_sceneManager.getSceneSummary(width)` but we need width.
      // Let's fix SceneManager usage or just pass a standard valid width (e.g. 720).
      
      String sceneSummary = _sceneManager.getSceneSummary(); // Uses stored width
      
      String response = await _apiService.chatWithGemini(sceneSummary, query);
      
      setState(() => _statusText = response);
      await _ttsService.speak(response);
    } else {
      setState(() => _statusText = "Didn't hear you.");
      await _ttsService.speak("I didn't hear a question.");
    }

    // Resume
    setState(() => _isListening = false);
    _startLiveFeed();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraService.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Prepare Painter
    // We need to pass the detections.
    // NOTE: We need to handle scaling.
    // CameraPreview fits the screen.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera View
          Positioned.fill(
            child: CameraPreview(_cameraService.controller!),
          ),
          
          // Bounding Boxes
          Positioned.fill(
             child: CustomPaint(
               painter: CameraPainter(detections: _detections),
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
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Voice Query Button
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: GestureDetector(
                onTap: _handleUserQuery,
                onDoubleTap: () {
                    // Double tap could trigger a silent "Read Scene"
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _isListening ? Colors.redAccent : Colors.blueAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withOpacity(0.5), blurRadius: 20, spreadRadius: 5)
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.hearing : Icons.mic,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
          
          // Hint Text
          const Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Text(
              "Tap mic to ask about the scene",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          )
        ],
      ),
    );
  }
}
