import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:uuid/uuid.dart';

class NavigationService {
  
  final String _googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  
  // Directions API Base URL
  final String _directionsUrl = "https://maps.googleapis.com/maps/api/directions/json";
  
  // Places API Base URL (New Text Search)
  final String _placesUrl = "https://places.googleapis.com/v1/places:searchText";

  // Autocomplete URL (Places API)
  final String _autocompleteUrl = "https://maps.googleapis.com/maps/api/place/autocomplete/json";
  
  // Place Details URL
  final String _placeDetailsUrl = "https://maps.googleapis.com/maps/api/place/details/json";

  final Uuid _uuid = const Uuid();
  String? _sessionToken;
  http.Client? _suggestionClient;

  NavigationService() {
      // Initialize a session token for autocomplete
      _sessionToken = _uuid.v4();
  }

  /// Geocodes an address or Place ID to a LatLng.
  /// Ideally, use Place Details if you have a Place ID from autocomplete.
  Future<LatLng?> getCoordinates(String address) async {
      // Fallback: Text Search if manual entry
      final url = Uri.parse("https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=$_googleApiKey");
      
      print("🌍 Geocoding Request URL: $url");
      
      try {
          final response = await http.get(url);
          
          print("📡 Geocoding Response Status: ${response.statusCode}");
          print("📄 Geocoding Response Body: ${response.body}");
          
          if (response.statusCode == 200) {
              final data = json.decode(response.body);
              if (data['status'] == 'OK' && data['results'].isNotEmpty) {
                  final loc = data['results'][0]['geometry']['location'];
                  return LatLng(loc['lat'], loc['lng']);
              } else {
                  print("❌ Geocoding API Error: ${data['status']} - ${data['error_message'] ?? 'No error message'}");
              }
          }
      } catch (e) {
          print("❌ Geocoding Exception: $e");
      }
      return null;
  }
  
  Future<LatLng?> getPlaceDetails(String placeId) async {
       // New Places API (New) - Get Place endpoint
       final url = Uri.parse("https://places.googleapis.com/v1/$placeId");
       
       print("📍 Place Details Request URL: $url");
       
       try {
           final response = await http.get(
             url,
             headers: {
               'X-Goog-Api-Key': _googleApiKey,
               'X-Goog-FieldMask': 'location',
             },
           );
           
           print("📡 Place Details Response Status: ${response.statusCode}");
           print("📄 Place Details Response Body: ${response.body}");
           
           if (response.statusCode == 200) {
               final data = json.decode(response.body);
               if (data['location'] != null) {
                   final loc = data['location'];
                   // Reset session token after a successful selection
                   _sessionToken = _uuid.v4();
                   return LatLng(loc['latitude'], loc['longitude']);
               } else {
                   print("❌ Place Details Error: No location in response");
               }
           } else {
               print("❌ Place Details Error: Status ${response.statusCode}");
           }
       } catch (e) {
           print("❌ Place Details Exception: $e");
       }
       return null;
  }

  /// Fetches a list of address suggestions for a query string.
  Future<List<Map<String, dynamic>>> getSuggestions(String query) async {
    if (query.length < 3) return []; 
    
    // Cancel previous
    _suggestionClient?.close();
    _suggestionClient = http.Client();
    
    // New Places API (New) - Autocomplete endpoint
    final url = Uri.parse("https://places.googleapis.com/v1/places:autocomplete");

    print("🔍 Autocomplete Request URL: $url");
    print("🔑 API Key (first 10 chars): ${_googleApiKey.substring(0, 10)}...");

    try {
      // New API uses POST with JSON body
      final response = await _suggestionClient!.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _googleApiKey,
        },
        body: json.encode({
          'input': query,
          'sessionToken': _sessionToken,
        }),
      );

      print("📡 Autocomplete Response Status: ${response.statusCode}");
      print("📄 Autocomplete Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['suggestions'] != null) {
            return List<Map<String, dynamic>>.from(data['suggestions'].map((s) {
                final placePrediction = s['placePrediction'];
                if (placePrediction != null) {
                  return {
                    'description': placePrediction['text']?['text'] ?? '',
                    'place_id': placePrediction['placeId'] ?? '',
                  };
                }
                return null;
            }).where((item) => item != null));
        } else {
            print("❌ Autocomplete API Error: No suggestions in response");
        }
      } else {
        print("❌ Autocomplete API Error: Status ${response.statusCode}");
      }
    } catch (e) {
       print("❌ Autocomplete Exception: $e");
    }
    return [];
  }

  /// Fetches a route between start and end points using Google Directions API.
  Future<Map<String, dynamic>?> getRoute(LatLng start, LatLng end) async {
    final origin = "${start.latitude},${start.longitude}";
    final destination = "${end.latitude},${end.longitude}";
    
    final url = Uri.parse("$_directionsUrl?origin=$origin&destination=$destination&mode=driving&key=$_googleApiKey");

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
           return data;
        } else {
            print("Directions API Error: ${data['status']} - ${data['error_message']}");
        }
      }
    } catch (e) {
      print("Routing Error: $e");
    }
    return null;
  }
  
  /// Helper to decode Polyline
  List<LatLng> decodePolyline(String encoded) {
      PolylinePoints polylinePoints = PolylinePoints();
      List<PointLatLng> result = polylinePoints.decodePolyline(encoded);
      return result.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }
}
