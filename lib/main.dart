import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/camera_service.dart';
import 'services/tts_service.dart';
import 'services/api_service.dart';
import 'services/audio_service.dart';
import 'services/logging_service.dart';
import 'services/voice_control_service.dart';
import 'services/yolo_service.dart';
import 'services/scene_manager.dart';
import 'services/contact_service.dart';
import 'services/sos_service.dart';
import 'services/face_storage_service.dart';
import 'services/face_recognition_service.dart';

import 'widgets/camera_painter.dart';
import 'screens/feature_carousel.dart';
import 'screens/sos_countdown_screen.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await LoggingService().initialize(); // Initialize logging early
  runApp(const VisionApp());
}

class VisionApp extends StatefulWidget {
  const VisionApp({super.key});

  @override
  State<VisionApp> createState() => _VisionAppState();
}

class _VisionAppState extends State<VisionApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
  // Singletons or App-Level Services
  final ContactService _contactService = ContactService();
  final TTSService _ttsService = TTSService();
  final VoiceControlService _voiceService = VoiceControlService();
  final FaceStorageService _faceStorage = FaceStorageService();
  late FaceRecognitionService _faceRecognition;
  late SosService _sosService;

  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  void _initializeApp() async {
    await _ttsService.initialize();
    await _contactService.initialize();
    await _faceStorage.initialize();
    
    _faceRecognition = FaceRecognitionService(_faceStorage);
    await _faceRecognition.initialize();
    
    _sosService = SosService(_contactService, _ttsService);
    
    // Initialize SOS Fall Detection
    _sosService.initialize(() {
        // On Fall Detected
        _navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => SosCountdownScreen(
                sosService: _sosService,
                ttsService: _ttsService,
                voiceService: _voiceService,
            ))
        );
    });
    // Start Monitoring Immediately
    _sosService.startMonitoring();
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _sosService.stopMonitoring();
    _faceRecognition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text("Initializing Vision AI...", style: TextStyle(fontSize: 18))
              ],
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Vision Assistant',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
      ),
      home: FeatureCarousel(
        contactService: _contactService,
        ttsService: _ttsService,
        faceStorage: _faceStorage,
        faceRecognition: _faceRecognition,
      ), 
    );
  }
}

class VisionHomePage extends StatefulWidget {
  final bool isActive;
  const VisionHomePage({super.key, this.isActive = true});

  @override
  State<VisionHomePage> createState() => _VisionHomePageState();
}

class _VisionHomePageState extends State<VisionHomePage> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final CameraService _cameraService = CameraService();
  final TTSService _ttsService = TTSService(); // Re-instantiated or could be passed
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
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sceneManager = SceneManager(_ttsService);
    if (widget.isActive) {
       _initializeServices();
    }
  }

  @override
  void didUpdateWidget(VisionHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      // Switched TO this page
      if (!_cameraService.isInitialized) {
        _initializeServices();
      } else {
        _startLiveFeed();
      }
    } else if (!widget.isActive && oldWidget.isActive) {
      // Switched AWAY from this page
      _cameraService.stopImageStream();
      _cameraService.dispose(); // Fully release camera for other tabs
    }
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
      Permission.sms, // Added SMS permission
      Permission.location, // Added Location permission
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.microphone]!.isGranted) {
      
      await _loggingService.initialize();
      await _ttsService.initialize();
      await _cameraService.initialize();
      await _yoloService.initialize();

      if (_yoloService.isLoaded && _cameraService.isInitialized) {
        if (mounted) setState(() => _statusText = "Starting Vision...");
        _startLiveFeed();
        // Ensure TTS is ready
        await _ttsService.speak("Vision Ready."); 
      } else {
        if (mounted) setState(() => _statusText = "Initialization Failed");
      }
    } else {
      if (mounted) setState(() => _statusText = "Permissions denied");
    }
  }

  void _startLiveFeed() {
    _cameraService.startImageStream((CameraImage image) async {
      if (_isProcessingFrame) return;

      _isProcessingFrame = true;
      try {
        final detections = await _yoloService.runInference(image);
        
        // Use the image width from the camera image for spatial calculations
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
    setState(() {
      _isListening = true;
      _statusText = "Listening for query...";
    });
    
    await _cameraService.stopImageStream(); // Pause vision to save resource/noise

    String? query = await _voiceService.listenForQuery();
    
    if (query != null && query.isNotEmpty) {
      setState(() => _statusText = "Thinking...");
      
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    if (!_cameraService.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
