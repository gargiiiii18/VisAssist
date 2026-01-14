import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class NavigationService {
  
  // OSRM Base URL (Demo Server)
  // NOTE: For production, you should host your own OSRM server or use a paid provider limit.
  final String _osrmBaseUrl = "https://router.project-osrm.org/route/v1/driving";
  
  // Nominatim Base URL (OpenStreetMap Geocoding)
  final String _nominatimUrl = "https://nominatim.openstreetmap.org/search";

  /// Geocodes an address string to a LatLng.
  Future<LatLng?> getCoordinates(String address) async {
    final url = Uri.parse("$_nominatimUrl?q=$address&format=json&limit=1");
    try {
      final response = await http.get(url, headers: {
        // User-Agent is required by Nominatim
        'User-Agent': 'FlutterVisionApp/1.0' 
      });

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (data.isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          return LatLng(lat, lon);
        }
      }
    } catch (e) {
      print("Geocoding Error: $e");
    }
    return null;
  }

  /// Fetches a list of address suggestions for a query string.
  Future<List<Map<String, dynamic>>> getSuggestions(String query) async {
    if (query.length < 3) return []; // optimization
    
    final url = Uri.parse("$_nominatimUrl?q=$query&format=json&addressdetails=1&limit=5");
    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'FlutterVisionApp/1.0' 
      });

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
    } catch (e) {
      print("Autocomplete Error: $e");
    }
    return [];
  }

  /// Fetches a route between start and end points using OSRM.
  Future<Map<String, dynamic>?> getRoute(LatLng start, LatLng end) async {
    // OSRM Format: {lon},{lat};{lon},{lat}
    final String coordinates = "${start.longitude},${start.latitude};${end.longitude},${end.latitude}";
    final url = Uri.parse("$_osrmBaseUrl/$coordinates?steps=true&geometries=geojson&overview=full");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print("OSRM Error: ${response.statusCode} ${response.body}");
      }
    } catch (e) {
      print("Routing Error: $e");
    }
    return null;
  }
}
