import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/tts_service.dart';

class ContactsPage extends StatefulWidget {
  final ContactService contactService;
  final TTSService ttsService;

  const ContactsPage({
    super.key,
    required this.contactService,
    required this.ttsService,
  });

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage> {
  List<Map<dynamic, dynamic>> _contacts = [];
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _numberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshContacts();
  }

  void _refreshContacts() {
    setState(() {
      _contacts = widget.contactService.getContacts();
    });
  }

  void _addContact() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Emergency Contact"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: _numberController,
              decoration: const InputDecoration(labelText: "Phone Number"),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_nameController.text.isNotEmpty && _numberController.text.isNotEmpty) {
                await widget.contactService.addContact(
                  _nameController.text,
                  _numberController.text,
                );
                _nameController.clear();
                _numberController.clear();
                Navigator.pop(context);
                _refreshContacts();
                widget.ttsService.speak("Contact added.");
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _deleteContact(int index) async {
      await widget.contactService.removeContact(index);
      _refreshContacts();
      widget.ttsService.speak("Contact removed.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Emergency Contacts"),
        backgroundColor: Colors.black,
      ),
      body: _contacts.isEmpty 
          ? const Center(
              child: Text(
                  "No contacts added.\nAdd people to alert in case of emergency.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return  Card(
                  color: Colors.grey[900],
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(contact['name'], style: const TextStyle(color: Colors.white, fontSize: 20)),
                    subtitle: Text(contact['number'], style: const TextStyle(color: Colors.white70)),
                    trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _deleteContact(index),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        label: const Text("Add Contact", style: TextStyle(fontSize: 18)),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blueAccent,
      ),
    );
  }
}
