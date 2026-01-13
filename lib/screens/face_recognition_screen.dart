import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/face_recognition_service.dart';
import '../services/face_storage_service.dart';
import '../services/tts_service.dart';
import '../widgets/face_detection_painter.dart';
import '../models/registered_face.dart';
import 'face_registration_screen.dart';
import 'manage_faces_screen.dart';

class FaceRecognitionScreen extends StatefulWidget {
  final FaceRecognitionService faceRecognition;
  final FaceStorageService faceStorage;
  final TTSService ttsService;
  final bool isActive;

  const FaceRecognitionScreen({
    super.key,
    required this.faceRecognition,
    required this.faceStorage,
    required this.ttsService,
    this.isActive = false,
  });

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  bool _isPaused = false;
  bool _isFrontCamera = true;
  List<CameraDescription> _cameras = [];
  List<DetectedFaceInfo> _detectedFaces = [];
  Timer? _processingTimer;
  Size _imageSize = const Size(1, 1);
  
  // Track announced faces to avoid repetition
  final Set<String> _announcedFaces = {};
  DateTime? _lastAnnouncementTime;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _initializeCamera();
    }
  }

  @override
  void didUpdateWidget(FaceRecognitionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initializeCamera();
    } else if (!widget.isActive && oldWidget.isActive) {
      _pauseCamera();
      _cameraController?.dispose();
      _cameraController = null;
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == (_isFrontCamera ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {});
        _startProcessing();
      }
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  Future<void> _toggleCamera() async {
    _pauseCamera();
    
    // Dispose old controller
    final oldController = _cameraController;
    
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _detectedFaces = []; 
      _cameraController = null; // Show loader, prevent red screen
    });
    
    await oldController?.dispose();
    await _initializeCamera();
    
    // Ensure we resume processing after flip
    _resumeCamera();
  }

  void _startProcessing() {
    if (_isPaused) return; // Don't start if paused
    // Process frames every 300ms to avoid overheating
    _processingTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!_isProcessing && mounted && !_isPaused) {
        _processFrame();
      }
    });
  }

  void _pauseCamera() {
    print(">>> [FACE REC] Pausing camera");
    _isPaused = true;
    _processingTimer?.cancel();
  }

  void _resumeCamera() {
    print(">>> [FACE REC] Resuming camera");
    _isPaused = false;
    if (mounted && _cameraController != null) {
      _startProcessing();
    }
  }

  Future<void> _processFrame() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _isProcessing = true;

    try {
      final image = await _cameraController!.takePicture();
      final inputImage = InputImage.fromFilePath(image.path);

      // Detect faces
      final faces = await widget.faceRecognition.detectFaces(inputImage);

      if (faces.isEmpty) {
        if (mounted) {
          setState(() {
            _detectedFaces = [];
          });
        }
        _isProcessing = false;
        return;
      }

      // Load full image for embedding generation
      final bytes = await image.readAsBytes();
      final decodedImage = img.decodeImage(bytes);

      if (decodedImage == null) {
        _isProcessing = false;
        return;
      }

      // Bake orientation to ensure pixels match EXIF metadata
      final fullImage = img.bakeOrientation(decodedImage);

      if (mounted && !_isPaused) {
        setState(() {
          // Store image size for painter
          _imageSize = Size(fullImage.width.toDouble(), fullImage.height.toDouble());
        });
      }

      List<DetectedFaceInfo> faceInfoList = [];

      for (var face in faces) {
        // Crop and generate embedding
        final faceImage = widget.faceRecognition.cropFace(fullImage, face);
        
        if (faceImage == null) continue;

        final embedding = await widget.faceRecognition.generateEmbedding(faceImage);

        if (embedding == null) continue;

        // Find match
        final match = widget.faceRecognition.findMatch(embedding);

        if (match != null) {
          final label = "${match.name}, ${match.relationship}";
          faceInfoList.add(DetectedFaceInfo(
            boundingBox: face.boundingBox,
            isRecognized: true,
            label: label,
          ));

          // Announce if not recently announced
          _announceIfNew(match);
        } else {
          faceInfoList.add(DetectedFaceInfo(
            boundingBox: face.boundingBox,
            isRecognized: false,
          ));
        }
      }

      if (mounted && !_isPaused) {
        setState(() {
          _detectedFaces = faceInfoList;
        });
      }
    } catch (e) {
      print("Error processing frame: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _announceIfNew(RegisteredFace face) {
    final now = DateTime.now();
    
    // Only announce if:
    // 1. Face hasn't been announced in this session, OR
    // 2. Last announcement was more than 10 seconds ago
    if (!_announcedFaces.contains(face.id) ||
        (_lastAnnouncementTime != null && 
         now.difference(_lastAnnouncementTime!).inSeconds > 10)) {
      
      widget.ttsService.speak("${face.name}, ${face.relationship} detected.");
      _announcedFaces.add(face.id);
      _lastAnnouncementTime = now;
    }
  }

  void _navigateToRegistration() async {
    _pauseCamera(); // Stop processing
    
    // Release hardware for the new screen
    final oldController = _cameraController;
    setState(() {
      _cameraController = null;
    });
    await oldController?.dispose();
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceRegistrationScreen(
          faceRecognition: widget.faceRecognition,
          faceStorage: widget.faceStorage,
          ttsService: widget.ttsService,
        ),
      ),
    );

    // Give sub-screen a moment to fully dispose its camera hardware
    await Future.delayed(const Duration(milliseconds: 300));

    // Re-initialize when coming back
    if (mounted && widget.isActive) {
      await _initializeCamera();
      _resumeCamera();
    }
    
    if (result == true) {
      widget.ttsService.speak("Face registered successfully.");
    }
  }

  void _navigateToManageFaces() async {
    _pauseCamera(); // Stop processing
    
    // Release hardware for the new screen (Manage screen doesn't use camera, but it's safer to release)
    final oldController = _cameraController;
    setState(() {
      _cameraController = null;
    });
    await oldController?.dispose();
    
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManageFacesScreen(
          faceStorage: widget.faceStorage,
          ttsService: widget.ttsService,
        ),
      ),
    );
    
    // Give sub-screen a moment to fully dispose its camera hardware
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Re-initialize when coming back
    if (mounted && widget.isActive) {
      await _initializeCamera();
      _resumeCamera();
    }
}

  @override
  void dispose() {
    _processingTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview
          Positioned.fill(
            child: CameraPreview(
              _cameraController!,
              key: ValueKey(_cameraController.hashCode), // Force rebuild on new controller
            ),
          ),

          // Face Detection Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: FaceDetectionPainter(
                detectedFaces: _detectedFaces,
                imageSize: _imageSize,
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
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _detectedFaces.isEmpty
                    ? "No faces detected"
                    : "${_detectedFaces.where((f) => f.isRecognized).length} recognized, ${_detectedFaces.where((f) => !f.isRecognized).length} unknown",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // Action Buttons
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Camera toggle button
                FloatingActionButton(
                  mini: true,
                  onPressed: _toggleCamera,
                  backgroundColor: Colors.black87,
                  heroTag: "camera_toggle",
                  child: Icon(
                    _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                    color: Colors.white,
                  ),
                ),
                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.extended(
                      onPressed: _navigateToRegistration,
                      icon: const Icon(Icons.person_add),
                      label: const Text("Register"),
                      backgroundColor: Colors.blueAccent,
                      heroTag: "register",
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton.extended(
                      onPressed: _navigateToManageFaces,
                      icon: const Icon(Icons.people),
                      label: const Text("Manage"),
                      backgroundColor: Colors.green,
                      heroTag: "manage",
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
