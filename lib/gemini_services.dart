import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:viora/secrets_gemini.dart';

class GeminiService {
  Future<String> getResponse(String prompt) async {
    try {
      final uri = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "gemini-flash-latest:generateContent?key=YOUR_API_KEY",
      );

      final response = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                { "text": prompt }
              ]
            }
          ]
        }),
      );

      debugPrint("Gemini status: ${response.statusCode}");
      debugPrint("Gemini body: ${response.body}");

      if (response.statusCode != 200) {
        return "Gemini API error.";
      }

      final data = jsonDecode(response.body);
      return data["candidates"][0]["content"]["parts"][0]["text"].trim();
    } catch (e) {
      debugPrint("Gemini exception: $e");
      return "Exception occurred.";
    }
  }
}
