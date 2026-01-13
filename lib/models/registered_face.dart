import 'package:hive/hive.dart';

part 'registered_face.g.dart';

@HiveType(typeId: 1)
class RegisteredFace extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String relationship;

  @HiveField(3)
  List<double> embedding; // 128-d vector for MobileFaceNet

  @HiveField(4)
  DateTime registeredAt;

  RegisteredFace({
    required this.id,
    required this.name,
    required this.relationship,
    required this.embedding,
    required this.registeredAt,
  });

  // Helper to create unique ID
  static String generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  @override
  String toString() {
    return 'RegisteredFace(id: $id, name: $name, relationship: $relationship, registeredAt: $registeredAt)';
  }
}
