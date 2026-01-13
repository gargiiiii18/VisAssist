import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/registered_face.dart';
import 'face_storage_service.dart';

class FaceRecognitionService {
  Interpreter? _interpreter;
  FaceDetector? _faceDetector;
  final FaceStorageService _storage;
  
  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // MobileFaceNet parameters
  static const int inputSize = 112; // MobileFaceNet uses 112x112
  static const int embeddingSize = 128; // MobileFaceNet outputs 128-d (not 192-d)
  static const double matchThreshold = 0.7; // Cosine similarity threshold

  FaceRecognitionService(this._storage);

  Future<void> initialize() async {
    try {
      // Load MobileFaceNet model
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      print("MobileFaceNet model loaded successfully");

      // Initialize ML Kit Face Detector
      final options = FaceDetectorOptions(
        enableContours: false,
        enableLandmarks: false,
        enableClassification: false,
        enableTracking: false,
        minFaceSize: 0.05, // More sensitive (5% instead of 15%)
        performanceMode: FaceDetectorMode.fast,
      );
      _faceDetector = FaceDetector(options: options);
      
      _isLoaded = true;
      print("FaceRecognitionService initialized");
    } catch (e) {
      print("Error loading face recognition model: $e");
      _isLoaded = false;
    }
  }

  /// Detect faces in camera image using ML Kit
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    if (_faceDetector == null) return [];
    try {
      final faces = await _faceDetector!.processImage(inputImage);
      return faces;
    } catch (e) {
      print("Error detecting faces: $e");
      return [];
    }
  }

  /// Generate 192-d embedding from face image
  Future<List<double>?> generateEmbedding(img.Image faceImage) async {
    if (_interpreter == null) return null;

    try {
      // Resize to 112x112 for MobileFaceNet
      final resized = img.copyResize(faceImage, width: inputSize, height: inputSize);
      
      // Normalize to [-1, 1] range and reshape to [1, 112, 112, 3]
      final input = _imageToByteListFloat32(resized);
      final inputReshaped = input.reshape([1, inputSize, inputSize, 3]);
      
      // Output buffer for 192-d embedding
      final output = List.filled(1 * embeddingSize, 0.0).reshape([1, embeddingSize]);
      
      print(">>> [FACE REC SERVICE] Running inference with input shape: [1, $inputSize, $inputSize, 3]");
      
      // Run inference
      _interpreter!.run(inputReshaped, output);
      
      print(">>> [FACE REC SERVICE] Inference complete, output shape: [1, $embeddingSize]");
      
      // Extract embedding
      final embedding = List<double>.from(output[0]);
      
      // Normalize embedding (L2 normalization)
      return _normalizeEmbedding(embedding);
    } catch (e, stackTrace) {
      print(">>> [FACE REC SERVICE] Error generating embedding: $e");
      print(">>> [FACE REC SERVICE] Stack trace: $stackTrace");
      return null;
    }
  }

  /// Convert image to Float32 input for model
  Float32List _imageToByteListFloat32(img.Image image) {
    final convertedBytes = Float32List(1 * inputSize * inputSize * 3);
    final buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = image.getPixel(x, y);
        
        // Normalize to [-1, 1]
        buffer[pixelIndex++] = (pixel.r / 127.5) - 1.0;
        buffer[pixelIndex++] = (pixel.g / 127.5) - 1.0;
        buffer[pixelIndex++] = (pixel.b / 127.5) - 1.0;
      }
    }
    return convertedBytes;
  }

  /// L2 normalize embedding vector
  List<double> _normalizeEmbedding(List<double> embedding) {
    double sum = 0.0;
    for (var val in embedding) {
      sum += val * val;
    }
    final magnitude = sqrt(sum);
    return embedding.map((val) => val / magnitude).toList();
  }

  /// Calculate cosine similarity between two embeddings
  double cosineSimilarity(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) {
      throw ArgumentError('Embeddings must have same length');
    }

    double dotProduct = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      dotProduct += embedding1[i] * embedding2[i];
    }
    
    // Since embeddings are already normalized, cosine similarity = dot product
    return dotProduct;
  }

  /// Find best match for given embedding
  RegisteredFace? findMatch(List<double> embedding) {
    final registeredFaces = _storage.getAllFaces();
    if (registeredFaces.isEmpty) return null;

    RegisteredFace? bestMatch;
    double bestSimilarity = -1.0;

    for (var face in registeredFaces) {
      final similarity = cosineSimilarity(embedding, face.embedding);
      if (similarity > bestSimilarity && similarity >= matchThreshold) {
        bestSimilarity = similarity;
        bestMatch = face;
      }
    }

    if (bestMatch != null) {
      print("Match found: ${bestMatch.name} (similarity: ${bestSimilarity.toStringAsFixed(3)})");
    }

    return bestMatch;
  }

  /// Crop face from full image based on bounding box
  img.Image? cropFace(img.Image fullImage, Face face) {
    try {
      final boundingBox = face.boundingBox;
      
      // Add padding (10% on each side)
      final padding = (boundingBox.width * 0.1).toInt();
      final left = max(0, boundingBox.left.toInt() - padding);
      final top = max(0, boundingBox.top.toInt() - padding);
      final width = min(fullImage.width - left, boundingBox.width.toInt() + 2 * padding);
      final height = min(fullImage.height - top, boundingBox.height.toInt() + 2 * padding);
      
      return img.copyCrop(fullImage, x: left, y: top, width: width, height: height);
    } catch (e) {
      print("Error cropping face: $e");
      return null;
    }
  }

  void dispose() {
    _interpreter?.close();
    _faceDetector?.close();
    _isLoaded = false;
  }
}
