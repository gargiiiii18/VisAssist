import 'package:flutter/material.dart';
import '../services/face_storage_service.dart';
import '../services/tts_service.dart';
import '../models/registered_face.dart';
import 'package:intl/intl.dart';

class ManageFacesScreen extends StatefulWidget {
  final FaceStorageService faceStorage;
  final TTSService ttsService;

  const ManageFacesScreen({
    super.key,
    required this.faceStorage,
    required this.ttsService,
  });

  @override
  State<ManageFacesScreen> createState() => _ManageFacesScreenState();
}

class _ManageFacesScreenState extends State<ManageFacesScreen> {
  List<RegisteredFace> _faces = [];

  @override
  void initState() {
    super.initState();
    _loadFaces();
    widget.ttsService.speak("Manage Faces. ${widget.faceStorage.getFaceCount()} faces registered.");
  }

  void _loadFaces() {
    setState(() {
      _faces = widget.faceStorage.getAllFaces();
    });
  }

  void _deleteFace(RegisteredFace face) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Face"),
        content: Text("Are you sure you want to delete ${face.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.faceStorage.deleteFace(face.id);
      if (success) {
        widget.ttsService.speak("${face.name} deleted.");
        _loadFaces();
      }
    }
  }

  void _editFace(RegisteredFace face) async {
    final nameController = TextEditingController(text: face.name);
    final relationshipController = TextEditingController(text: face.relationship);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Face"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: relationshipController,
              decoration: const InputDecoration(labelText: "Relationship"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (result == true) {
      face.name = nameController.text.trim();
      face.relationship = relationshipController.text.trim();
      
      final success = await widget.faceStorage.updateFace(face);
      if (success) {
        widget.ttsService.speak("Face updated.");
        _loadFaces();
      }
    }

    nameController.dispose();
    relationshipController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Manage Faces"),
        backgroundColor: Colors.black,
      ),
      body: _faces.isEmpty
          ? const Center(
              child: Text(
                "No faces registered yet. Use the Register button to add faces.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _faces.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final face = _faces[index];
                final dateStr = DateFormat('MMM d, y').format(face.registeredAt);

                return Card(
                  color: Colors.grey[900],
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.face, color: Colors.white),
                    ),
                    title: Text(
                      face.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          face.relationship,
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Registered: $dateStr",
                          style: const TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blueAccent),
                          onPressed: () => _editFace(face),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _deleteFace(face),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
