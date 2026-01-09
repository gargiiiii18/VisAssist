import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service to handle interactions with the Gemini API.
class ApiService {
  final String _apiKey = 'AIzaSyA3FlBMLWJvFbR7QebewsnFeiOtSbJOLnY';
  final String _model = 'gemini-flash-lite-latest';

  /// Sends scene context and user query to Gemini.
  Future<String> chatWithGemini(String sceneContext, String userQuery) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');

    try {
      String systemPrompt = "You are an assistive vision AI. "
          "The user is visually impaired. "
          "Context: $sceneContext. "
          "User Query: \"$userQuery\". "
          "INSTRUCTIONS: Answer the user's query using the provided context. "
          "If the user asks where an object is, use the spatial information (left, center, right). "
          "Keep the answer brief, clear, and helpful. Do not mention that you are converting text to speech.";

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{
            "parts": [{"text": systemPrompt}]
          }],
          "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 256,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String? text = data['candidates'][0]['content']['parts'][0]['text'];
        return text?.trim() ?? "I couldn't understand the response.";
      } else {
        // print("API Error: ${response.body}");
        return "Sorry, I am unable to connect to the assistant right now.";
      }
    } catch (e) {
      // print("Exception during Gemini chat: $e");
      return "Error connecting to AI service.";
    }
  }
}
