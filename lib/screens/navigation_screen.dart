import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/navigation_service.dart';
import '../services/tts_service.dart';

class NavigationScreen extends StatefulWidget {
  final TTSService ttsService;

  const NavigationScreen({super.key, required this.ttsService});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> with AutomaticKeepAliveClientMixin {
  final NavigationService _navService = NavigationService();
  final MapController _mapController = MapController();
  final TextEditingController _destController = TextEditingController();
  
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  List<LatLng> _routePoints = [];
  List<dynamic> _steps = [];
  int _currentStepIndex = 0;
  bool _isNavigating = false;
  String _currentInstruction = "Enter destination to start";
  Box? _navBox;
  
  StreamSubscription<Position>? _positionStream;

  // Constants
  static const double _voiceTriggerDistance = 50.0; // meters
  static const double _rerouteThreshold = 50.0; // meters

  bool _isRecalculating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initPersistence();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _initPersistence() async {
      try {
        _navBox = await Hive.openBox('navigation');
        
        // Auto-resume?
        if (_navBox != null && _navBox!.containsKey('dest_lat')) {
            final lat = _navBox!.get('dest_lat');
            final lon = _navBox!.get('dest_lon');
            final name = _navBox!.get('dest_name');
            
            setState(() {
                _destinationLocation = LatLng(lat, lon);
                _destController.text = name ?? "Restored Destination";
                _isNavigating = true; // Set navigating true so UI shows map
                _currentInstruction = "Resuming navigation...";
            });
            
            // Wait for location to be ready then start
            // We loop check location for a bit
            int retries = 0;
            while (_currentLocation == null && retries < 10) {
               await Future.delayed(const Duration(milliseconds: 500));
               retries++;
            }
            
            if (_currentLocation != null) {
                _startNavigation(isResume: true);
            }
        }
      } catch (e) {
        print("Persistence Error: $e");
      }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return; 
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
  }

  void _startNavigation({bool isResume = false}) async {
    if (_destController.text.isEmpty || _currentLocation == null) {
      if (!isResume) widget.ttsService.speak("Please enter a destination and ensure GPS is on.");
      return;
    }
    
    // 1. Resolve Destination (if not already selected via Autocomplete)
    if (_destinationLocation == null) {
        final dest = await _navService.getCoordinates(_destController.text);
        if (dest == null) {
          widget.ttsService.speak("Address not found.");
          return;
        }
        _destinationLocation = dest;
    }
    
    // Save Persistence
    _navBox?.put('dest_lat', _destinationLocation!.latitude);
    _navBox?.put('dest_lon', _destinationLocation!.longitude);
    _navBox?.put('dest_name', _destController.text);

    // 2. Get Route
    final routeData = await _navService.getRoute(_currentLocation!, _destinationLocation!);
    if (routeData == null) {
      widget.ttsService.speak("Could not calculate route.");
      return;
    }

    // 3. Parse Route
    final route = routeData['routes'][0];
    final geometry = route['geometry']['coordinates'] as List; // GeoJSON [lon, lat]
    final legs = route['legs'][0];
    final steps = legs['steps'] as List;

    setState(() {
      _routePoints = geometry.map<LatLng>((p) => LatLng(p[1], p[0])).toList();
      _steps = steps;
      _currentStepIndex = 0;
      _isNavigating = true;
      _currentInstruction = "Starting navigation to ${_destController.text}";
    });
    
    // Center map
    _mapController.move(_currentLocation!, 15);
    widget.ttsService.speak("Starting navigation. ${_parseInstruction(steps[0])}");

    // 4. Start Tracking
    if (_positionStream == null) {
       _startLiveTracking();
    }
  }

  void _startLiveTracking() {
    _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation, 
            distanceFilter: 5 
        )
    ).listen((Position position) {
        final newLoc = LatLng(position.latitude, position.longitude);
        _currentLocation = newLoc;
        _mapController.move(newLoc, 16);
        
        _checkProgress(newLoc);
    });
  }

  void _checkProgress(LatLng currentLoc) {
    if (_isRecalculating || _routePoints.isEmpty) return;

    // 1. Check for Deviation
    if (_isOffRoute(currentLoc)) {
       _recalculateRoute(currentLoc);
       return;
    }

    if (_steps.isEmpty || _currentStepIndex >= _steps.length) {
       _finishNavigation();
       return;
    }

    // Check distance to next maneuver
    final currentStep = _steps[_currentStepIndex];
    final maneuverLoc = currentStep['maneuver']['location']; // [lon, lat]
    final maneuverLatLng = LatLng(maneuverLoc[1], maneuverLoc[0]);
    
    final distance = const Distance().as(LengthUnit.Meter, currentLoc, maneuverLatLng);
    
    if (distance < _voiceTriggerDistance) {
       // Announce next step
       if (_currentStepIndex + 1 < _steps.length) {
          final nextStep = _steps[_currentStepIndex + 1];
          final instruction = _parseInstruction(nextStep);
          
          if (_currentInstruction != instruction) { // Prevent repeat spam
              widget.ttsService.speak("In 50 meters, $instruction");
              setState(() {
                _currentInstruction = instruction;
                _currentStepIndex++;
              });
          }
       } else {
         _finishNavigation();
       }
    }
  }
  
  // --- Rerouting Logic ---

  bool _isOffRoute(LatLng currentPos) {
      if (_routePoints.length < 2) return false;

      double minDistance = double.infinity;
      const distanceCalc = Distance();

      // Find distance to closest segment
      for (int i = 0; i < _routePoints.length - 1; i++) {
          final start = _routePoints[i];
          final end = _routePoints[i+1];
          final d = _distanceToSegment(currentPos, start, end, distanceCalc);
          if (d < minDistance) minDistance = d;
          
          if (minDistance < _rerouteThreshold) return false; 
      }
      
      return minDistance > _rerouteThreshold;
  }
  
  double _distanceToSegment(LatLng P, LatLng A, LatLng B, Distance distanceCalc) {
      final double x = P.latitude; 
      final double y = P.longitude;
      
      final double x1 = A.latitude;
      final double y1 = A.longitude;
      
      final double x2 = B.latitude;
      final double y2 = B.longitude;

      final double A_x = x - x1;
      final double A_y = y - y1;
      final double B_x = x2 - x1;
      final double B_y = y2 - y1;

      final double dot = A_x * B_x + A_y * B_y;
      final double len_sq = B_x * B_x + B_y * B_y;
      
      double param = -1;
      if (len_sq != 0) // in case of 0 length line
          param = dot / len_sq;

      double xx, yy;

      if (param < 0) {
        xx = x1;
        yy = y1;
      } else if (param > 1) {
        xx = x2;
        yy = y2;
      } else {
        xx = x1 + param * B_x;
        yy = y1 + param * B_y;
      }

      return distanceCalc.as(LengthUnit.Meter, P, LatLng(xx, yy));
  }
  
  Future<void> _recalculateRoute(LatLng currentLoc) async {
      setState(() {
         _isRecalculating = true;
         _currentInstruction = "Recalculating...";
      });
      widget.ttsService.speak("Recalculating route.");
      
      final routeData = await _navService.getRoute(currentLoc, _destinationLocation!);
      
      if (routeData == null) {
         widget.ttsService.speak("Could not calculate new route.");
         setState(() => _isRecalculating = false);
         return;
      }

      final route = routeData['routes'][0];
      final geometry = route['geometry']['coordinates'] as List;
      final legs = route['legs'][0];
      final steps = legs['steps'] as List;

      if (mounted) {
        setState(() {
          _routePoints = geometry.map<LatLng>((p) => LatLng(p[1], p[0])).toList();
          _steps = steps;
          _currentStepIndex = 0;
          _isRecalculating = false;
        });
        
        if (steps.isNotEmpty) {
           final firstInstr = _parseInstruction(steps[0]);
           widget.ttsService.speak("New route found. $firstInstr");
           setState(() => _currentInstruction = firstInstr);
        }
      }
  }

  // --- End Rerouting Logic ---

  void _finishNavigation() {
     _isNavigating = false;
     _positionStream?.cancel();
     _positionStream = null;
     
     // Clear Persistence
     _navBox?.delete('dest_lat');
     _navBox?.delete('dest_lon');
     _navBox?.delete('dest_name');

     widget.ttsService.speak("Navigation stopped.");
     
     setState(() {
       _currentInstruction = "Navigation Stopped";
       _routePoints = [];
       _destController.clear();
       _destinationLocation = null;
     });
  }

  String _parseInstruction(Map step) {
      final type = step['maneuver']['type']; 
      final modifier = step['maneuver']['modifier'];
      final name = step['name']; 
      
      String text = "$type $modifier";
      if (name != null && name.toString().isNotEmpty) {
          text += " onto $name";
      }
      return text;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Turn-by-Turn Navigation"), 
        backgroundColor: Colors.black,
        actions: [
          if (_isNavigating)
             IconButton(
               icon: const Icon(Icons.cancel, color: Colors.red),
               onPressed: _finishNavigation,
               tooltip: "Stop Navigation",
             )
        ],
      ),
      body: Stack(
         children: [
            Column(
              children: [
                // Input Area
                if (!_isNavigating)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                       Autocomplete<Map<String, dynamic>>(
                         optionsBuilder: (TextEditingValue textEditingValue) async {
                           if (textEditingValue.text.isEmpty) {
                             return const Iterable<Map<String, dynamic>>.empty();
                           }
                           return await _navService.getSuggestions(textEditingValue.text);
                         },
                         displayStringForOption: (Map<String, dynamic> option) => option['display_name'] ?? '',
                         onSelected: (Map<String, dynamic> selection) {
                            final lat = double.parse(selection['lat']);
                            final lon = double.parse(selection['lon']);
                            
                            setState(() {
                               _destinationLocation = LatLng(lat, lon);
                               _destController.text = selection['display_name'];
                            });
                         },
                         fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                            textEditingController.addListener(() {
                               _destController.text = textEditingController.text;
                            });
                            
                            return TextField(
                             controller: textEditingController,
                             focusNode: focusNode,
                             decoration: const InputDecoration(
                               labelText: "Destination Address",
                               border: OutlineInputBorder(),
                               suffixIcon: Icon(Icons.search),
                               helperText: "Type generic places like 'Central Park' or addresses",
                             ),
                           );
                         },
                         optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                elevation: 4.0,
                                child: SizedBox(
                                  width: MediaQuery.of(context).size.width - 32, // Match padding
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option['display_name'] ?? ''),
                                        onTap: () {
                                          onSelected(option);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                         },
                       ),
                       const SizedBox(height: 10),
                       ElevatedButton(
                         onPressed: _startNavigation, 
                         child: const Text("Start Navigation"),
                       )
                    ],
                  ),
                ),

                // Map Area
                Expanded(
                  child: _currentLocation == null 
                    ? const Center(child: CircularProgressIndicator())
                    : FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: _currentLocation!,
                          initialZoom: 15.0,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.fyp_app',
                          ),
                          if (_routePoints.isNotEmpty)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _routePoints,
                                  strokeWidth: 4.0,
                                  color: Colors.blue,
                                ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              // Current Location
                              Marker(
                                point: _currentLocation!,
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.navigation, color: Colors.blue, size: 40),
                              ),
                              // Destination
                              if (_destinationLocation != null)
                                Marker(
                                  point: _destinationLocation!,
                                  width: 40,
                                  height: 40,
                                  child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                                ),
                            ],
                          ),
                        ],
                      ),
                ),
                
                // Instruction Overlay
                if (_isNavigating)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: Colors.blueAccent,
                  child: Text(
                    _currentInstruction,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                )
              ],
            ),
            
            // X Button Overlay (Alternative to AppBar)
            if (_isNavigating)
             Positioned(
                top: 20,
                right: 20,
                child: FloatingActionButton(
                   backgroundColor: Colors.red,
                   child: const Icon(Icons.close, color: Colors.white),
                   onPressed: _finishNavigation,
                ),
             ),
         ]
      ),
    );
  }
}
