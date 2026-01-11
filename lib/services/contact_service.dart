import 'package:hive_flutter/hive_flutter.dart';

class ContactService {
  static const String _boxName = 'sos_contacts';
  Box? _box;

  Future<void> initialize() async {
    try {
      await Hive.initFlutter();
      _box = await Hive.openBox(_boxName);
      print("ContactService: Hive Box initialized.");
    } catch (e) {
      print("ContactService: Hive Init Error: $e");
    }
  }

  /// Adds a new contact. Returns true if successful.
  Future<bool> addContact(String name, String number) async {
    if (_box == null) return false;
    try {
      final contact = {'name': name, 'number': number};
      await _box!.add(contact);
      return true;
    } catch (e) {
      print("Error adding contact: $e");
      return false;
    }
  }

  /// Removes a contact at [index].
  Future<void> removeContact(int index) async {
    if (_box == null) return;
    if (index >= 0 && index < _box!.length) {
      await _box!.deleteAt(index);
    }
  }

  /// Retrieves all contacts.
  List<Map<dynamic, dynamic>> getContacts() {
    if (_box == null) {
      print("Warning: Attempted to get contacts before box init.");
      return [];
    }
    return _box!.values.toList().cast<Map<dynamic, dynamic>>();
  }
}
