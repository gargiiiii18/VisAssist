import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../services/face_recognition_service.dart';
import '../services/face_storage_service.dart';
import '../services/tts_service.dart';
import '../models/registered_face.dart';

class FaceRegistrationScreen extends StatefulWidget {
  final FaceRecognitionService faceRecognition;
  final FaceStorageService faceStorage;
  final TTSService ttsService;

  const FaceRegistrationScreen({
    super.key,
    required this.faceRecognition,
    required this.faceStorage,
    required this.ttsService,
  });

  @override
  State<FaceRegistrationScreen> createState() => _FaceRegistrationScreenState();
}

class _FaceRegistrationScreenState extends State<FaceRegistrationScreen> {
  CameraController? _cameraController;
  bool _isProcessing = false;
  bool _faceDetected = false;
  List<double>? _capturedEmbedding;
  List<int>? _capturedImageBytes;
  bool _isFrontCamera = true;
  List<CameraDescription> _cameras = [];
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _relationshipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    widget.ttsService.speak("Face Registration. Point camera at face and tap capture.");
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
      if (mounted) setState(() {});
    } catch (e) {
      print("Camera initialization error: $e");
    }
  }

  Future<void> _toggleCamera() async {
    if (_isProcessing) return;
    
    setState(() {
      _isFrontCamera = !_isFrontCamera;
    });
    
    await _cameraController?.dispose();
    await _initializeCamera();
  }

  Future<void> _captureFace() async {
    if (_isProcessing || _cameraController == null) return;

    setState(() {
      _isProcessing = true;
      _faceDetected = false;
    });

    widget.ttsService.speak("Capturing face...");
    print(">>> [FACE REG] Starting face capture...");

    try {
      print(">>> [FACE REG] Taking picture...");
      final image = await _cameraController!.takePicture();
      print(">>> [FACE REG] Picture taken: ${image.path}");
      
      final inputImage = InputImage.fromFilePath(image.path);
      print(">>> [FACE REG] InputImage created");

      // Detect faces
      print(">>> [FACE REG] Detecting faces...");
      final faces = await widget.faceRecognition.detectFaces(inputImage);
      print(">>> [FACE REG] Faces detected: ${faces.length}");

      if (faces.isEmpty) {
        print(">>> [FACE REG] No face detected");
        widget.ttsService.speak("No face detected. Please try again.");
        setState(() => _isProcessing = false);
        return;
      }

      if (faces.length > 1) {
        print(">>> [FACE REG] Multiple faces detected");
        widget.ttsService.speak("Multiple faces detected. Please ensure only one person is in frame.");
        setState(() => _isProcessing = false);
        return;
      }

      // Load full image
      print(">>> [FACE REG] Loading image bytes...");
      final bytes = await image.readAsBytes();
      print(">>> [FACE REG] Decoding image...");
      final fullImage = img.decodeImage(bytes);
      
      if (fullImage == null) {
        print(">>> [FACE REG] ERROR: Failed to decode image");
        widget.ttsService.speak("Error processing image.");
        setState(() => _isProcessing = false);
        return;
      }
      print(">>> [FACE REG] Image decoded: ${fullImage.width}x${fullImage.height}");

      // Crop face
      print(">>> [FACE REG] Cropping face...");
      final faceImage = widget.faceRecognition.cropFace(fullImage, faces.first);
      
      if (faceImage == null) {
        print(">>> [FACE REG] ERROR: Failed to crop face");
        widget.ttsService.speak("Error cropping face.");
        setState(() => _isProcessing = false);
        return;
      }
      print(">>> [FACE REG] Face cropped: ${faceImage.width}x${faceImage.height}");

      // Generate embedding
      print(">>> [FACE REG] Generating embedding...");
      final embedding = await widget.faceRecognition.generateEmbedding(faceImage);
      print(">>> [FACE REG] Embedding generated: ${embedding?.length ?? 'NULL'}");

      if (embedding == null) {
        print(">>> [FACE REG] ERROR: Failed to generate embedding");
        widget.ttsService.speak("Error generating face data.");
        setState(() => _isProcessing = false);
        return;
      }

      print(">>> [FACE REG] SUCCESS! Embedding size: ${embedding.length}");
      
      // Step: Check if already registered
      final existingMatch = widget.faceRecognition.findMatch(embedding);
      if (existingMatch != null) {
          widget.ttsService.speak("This face is already registered as ${existingMatch.name}, ${existingMatch.relationship}.");
          
          setState(() {
            _isProcessing = false;
            _faceDetected = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Already registered as ${existingMatch.name} (${existingMatch.relationship})"),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return; // Stop here, don't show preview/form for existing face
      }

      // Stop camera once captured (new face)
      final oldController = _cameraController;
      setState(() {
        _cameraController = null;
        _capturedEmbedding = embedding;
        _capturedImageBytes = img.encodeJpg(faceImage);
        _faceDetected = true;
        _isProcessing = false;
      });
      await oldController?.dispose();

      widget.ttsService.speak("Face captured successfully. Please enter name and relationship.");
    } catch (e, stackTrace) {
      print(">>> [FACE REG] ERROR: $e");
      print(">>> [FACE REG] Stack trace: $stackTrace");
      widget.ttsService.speak("Error capturing face. Please try again.");
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveFace() async {
    if (_capturedEmbedding == null) return;
    if (_nameController.text.isEmpty || _relationshipController.text.isEmpty) {
      widget.ttsService.speak("Please enter both name and relationship.");
      return;
    }

    final face = RegisteredFace(
      id: RegisteredFace.generateId(),
      name: _nameController.text.trim(),
      relationship: _relationshipController.text.trim(),
      embedding: _capturedEmbedding!,
      registeredAt: DateTime.now(),
    );

    final success = await widget.faceStorage.addFace(face);

    if (success) {
      widget.ttsService.speak("Face registered for ${face.name}, ${face.relationship}.");
      if (mounted) Navigator.pop(context, true);
    } else {
      widget.ttsService.speak("Error saving face. Please try again.");
    }
  }

  Future<void> _onBack() async {
    final oldController = _cameraController;
    setState(() => _cameraController = null);
    await oldController?.dispose();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _nameController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_faceDetected && (_cameraController == null || !_cameraController!.value.isInitialized)) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        await _onBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text("Register Face"),
          backgroundColor: Colors.black,
          leading: IconButton(
            icon: const Icon(Icons.close, size: 30),
            onPressed: _onBack,
            tooltip: "Cancel registration",
          ),
        ),
        body: Column(
          children: [
            // Camera Preview
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                   if (_faceDetected && _capturedImageBytes != null)
                    Center(
                      child: Image.memory(
                        Uint8List.fromList(_capturedImageBytes!),
                        fit: BoxFit.contain,
                      ),
                    )
                  else if (_cameraController != null)
                    Center(child: CameraPreview(_cameraController!)),
                  
                  if (_faceDetected)
                    const Center(
                      child: Icon(Icons.check_circle, color: Colors.green, size: 100),
                    ),
                  // Camera toggle button
                  if (!_faceDetected)
                    Positioned(
                      bottom: 20,
                      left: 20,
                      child: FloatingActionButton(
                        mini: true,
                        onPressed: _isProcessing ? null : _toggleCamera,
                        backgroundColor: Colors.black87,
                        child: Icon(
                          _isFrontCamera ? Icons.camera_front : Icons.camera_rear,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ... rest of the body ...
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(20),
                color: Colors.grey[900],
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (!_faceDetected) ...[
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _captureFace,
                          icon: const Icon(Icons.camera_alt, size: 30),
                          label: Text(
                            _isProcessing ? "Processing..." : "Capture Face",
                            style: const TextStyle(fontSize: 20),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                            minimumSize: const Size(double.infinity, 60),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _nameController,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          decoration: const InputDecoration(
                            labelText: "Name",
                            labelStyle: TextStyle(color: Colors.white70, fontSize: 18),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white54),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: _relationshipController,
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                          decoration: const InputDecoration(
                            labelText: "Relationship (e.g., Father, Friend)",
                            labelStyle: TextStyle(color: Colors.white70, fontSize: 18),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white54),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.blueAccent),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _faceDetected = false;
                                    _capturedEmbedding = null;
                                    _capturedImageBytes = null;
                                    _nameController.clear();
                                    _relationshipController.clear();
                                  });
                                  _initializeCamera(); // Restart camera
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                child: const Text("Retake", style: TextStyle(fontSize: 18)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _saveFace,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(vertical: 15),
                                ),
                                child: const Text("Save Face", style: TextStyle(fontSize: 18)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
