import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service to handle interactions with the Gemini API.
class ApiService {
  final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  final String _model = 'gemini-2.5-flash';

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
        print("API Error: ${response.body}");
        final errorData = jsonDecode(response.body);
        String errorMsg = errorData['error']['message'] ?? "Unknown API Error";
        return "AI Error: $errorMsg";
      }
    } on SocketException {
      return "No Internet Connection. Please check your Wi-Fi or Data.";
    } catch (e) {
      print("Exception during Gemini chat: $e");
      return "Connection Error: ${e.toString()}";
    }
  }
}
