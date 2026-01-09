import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Service to handle interactions with the Gemini API.
class ApiService {
  final String _apiKey = 'AIzaSyA3FlBMLWJvFbR7QebewsnFeiOtSbJOLnY';
  final String _model = 'gemini-flash-lite-latest';

  /// Sends video and optional audio query to Gemini.
  Future<String> analyzeVideo({required File videoFile, File? audioFile}) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');

    try {
      final videoBytes = await videoFile.readAsBytes();
      final base64Video = base64Encode(videoBytes);

      String? base64Audio;
      if (audioFile != null && await audioFile.exists()) {
        final audioBytes = await audioFile.readAsBytes();
        base64Audio = base64Encode(audioBytes);
      }

      String systemPrompt = "Analyze this 10-second video of an indoor environment. ";
      
      if (base64Audio != null) {
        systemPrompt += "The user has provided a separate audio recording containing a possible query. "
            "INSTRUCTIONS: "
            "1. Listen to the audio. If it contains a clear question about the environment, answer it accurately and concisely based on the video. "
            "2. If the audio is silent, contains only background noise, or does not have a recognizable question, IGNORE the audio entirely. "
            "3. In the case of NO clear question, respond ONLY with a comma-separated list of the most prominent objects visible in the video. "
            "4. NEVER mention audio quality or that you couldn't understand the user. Just provide the object list as the default response.";
      } else {
        systemPrompt += "Identify only the MOST PROMINENT objects visible. Focus on items that are centrally located, "
            "held in focus, or visible for a significant portion (at least 3-4 seconds) of the video. "
            "Ignore fleeting objects. Respond ONLY with a comma-separated list of these item names.";
      }

      final List<Map<String, dynamic>> parts = [
        {"text": systemPrompt},
        {
          "inline_data": {
            "mime_type": "video/mp4",
            "data": base64Video,
          }
        },
      ];

      if (base64Audio != null) {
        parts.add({
          "inline_data": {
            "mime_type": "audio/m4a",
            "data": base64Audio,
          }
        });
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": parts}],
          "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 1024,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'];
        return text?.trim() ?? "No objects identified.";
      } else {
        print("API Error: ${response.body}");
        return "Analysis failed.";
      }
    } catch (e) {
      print("Exception during video analysis: $e");
      return "Error connecting to AI service.";
    }
  }

  /// Uses Gemini to map an audio query to a store aisle and provide directions.
  Future<String> analyzeNavigationQuery({required File audioFile, required String storeMapContext}) async {
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');

    try {
      final audioBytes = await audioFile.readAsBytes();
      final base64Audio = base64Encode(audioBytes);

      String systemPrompt = "You are a store navigation assistant for the visually impaired. "
          "You are provided with a hardcoded map of the store aisles and their contents:\n\n"
          "$storeMapContext\n\n"
          "The user is asking for the location of an item in the provided audio. "
          "INSTRUCTIONS: "
          "1. Identify the item the user is looking for from the audio. "
          "2. Match that item to the most relevant Aisle in the map context above. "
          "3. Respond with a clear sentence that identifies the aisle and provides the EXACT directions listed for that aisle. "
          "4. If the item is not found in any aisle categories, use your intuition to pick the most logical aisle (e.g., 'Pens' belong in 'Stationery'). "
          "5. If the item is completely irrelevant to a shopping store, politely say you couldn't find it in the store layout. "
          "6. Keep the response concise and oriented toward a blind user.";

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": systemPrompt},
                {
                  "inline_data": {
                    "mime_type": "audio/m4a",
                    "data": base64Audio,
                  }
                },
              ]
            }
          ],
          "generationConfig": {
            "temperature": 0.2,
            "maxOutputTokens": 512,
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'];
        return text?.trim() ?? "No directions found.";
      } else {
        print("Navigation API Error: ${response.body}");
        return "Navigation service is currently unreachable.";
      }
    } catch (e) {
      print("Navigation Exception: $e");
      return "Something went wrong with the navigation query.";
    }
  }
}
