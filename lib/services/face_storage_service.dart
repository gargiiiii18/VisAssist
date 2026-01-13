import 'package:hive_flutter/hive_flutter.dart';
import '../models/registered_face.dart';

class FaceStorageService {
  static const String _boxName = 'registered_faces';
  Box<RegisteredFace>? _box;

  Future<void> initialize() async {
    try {
      // Register adapter if not already registered
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(RegisteredFaceAdapter());
      }
      
      _box = await Hive.openBox<RegisteredFace>(_boxName);
      print("FaceStorageService: Hive Box initialized with ${_box!.length} faces.");
    } catch (e) {
      print("FaceStorageService: Hive Init Error: $e");
    }
  }

  /// Add a new registered face
  Future<bool> addFace(RegisteredFace face) async {
    if (_box == null) return false;
    try {
      await _box!.put(face.id, face);
      print("Face added: ${face.name}");
      return true;
    } catch (e) {
      print("Error adding face: $e");
      return false;
    }
  }

  /// Get all registered faces
  List<RegisteredFace> getAllFaces() {
    if (_box == null) {
      print("Warning: Attempted to get faces before box init.");
      return [];
    }
    return _box!.values.toList();
  }

  /// Get face by ID
  RegisteredFace? getFaceById(String id) {
    if (_box == null) return null;
    return _box!.get(id);
  }

  /// Update existing face
  Future<bool> updateFace(RegisteredFace face) async {
    if (_box == null) return false;
    try {
      await _box!.put(face.id, face);
      print("Face updated: ${face.name}");
      return true;
    } catch (e) {
      print("Error updating face: $e");
      return false;
    }
  }

  /// Delete face by ID
  Future<bool> deleteFace(String id) async {
    if (_box == null) return false;
    try {
      await _box!.delete(id);
      print("Face deleted: $id");
      return true;
    } catch (e) {
      print("Error deleting face: $e");
      return false;
    }
  }

  /// Get count of registered faces
  int getFaceCount() {
    return _box?.length ?? 0;
  }

  /// Clear all faces (for testing/reset)
  Future<void> clearAll() async {
    if (_box != null) {
      await _box!.clear();
      print("All faces cleared.");
    }
  }
}
