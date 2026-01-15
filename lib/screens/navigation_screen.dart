import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  final TextEditingController _destController = TextEditingController();
  
  GoogleMapController? _mapController;
  
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  
  // Directions API Step Data
  List<dynamic> _steps = [];
  int _currentStepIndex = 0;
  
  bool _isNavigating = false;
  String _currentInstruction = "Enter destination to start";
  Box? _navBox;
  
  StreamSubscription<Position>? _positionStream;

  // Constants
  static const double _voiceTriggerDistance = 40.0; // meters
  static const double _rerouteThreshold = 60.0; // meters
  static const double _minMovementForReroute = 20.0; // meters

  LatLng? _lastRouteCalculationPoint;
  bool _isRecalculating = false;
  bool _manualCameraMove = false;
  bool _ignoreNextCameraMove = false;

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
    _mapController?.dispose();
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
                _isNavigating = true; 
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
      _updateMarkers();
    });
    
    // Animate camera if map is ready and not navigating yet
    if (_mapController != null && !_isNavigating) {
        _ignoreNextCameraMove = true;
        _mapController!.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: _currentLocation!, zoom: 15)
        ));
    }
  }

  void _startNavigation({bool isResume = false}) async {
    setState(() {
      _manualCameraMove = false;
    });
    if (_destController.text.isEmpty || _currentLocation == null) {
      if (!isResume) widget.ttsService.speak("Please enter a destination and ensure GPS is on.");
      return;
    }
    
    // 1. Resolve Destination
    if (_destinationLocation == null) {
        // Use text search fallback if no place ID selected
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
    final overviewPolyline = route['overview_polyline']['points'];
    final legs = route['legs'][0];
    final steps = legs['steps'] as List;

    // Decode polyline
    final List<LatLng> decodedPoints = _navService.decodePolyline(overviewPolyline);

    setState(() {
      _polylines = {
          Polyline(
              polylineId: const PolylineId("route"),
              points: decodedPoints,
              color: Colors.blue,
              width: 5
          )
      };
      _steps = steps;
      _currentStepIndex = 0;
      _isNavigating = true;
      _lastRouteCalculationPoint = _currentLocation;
      _currentInstruction = "Starting navigation to ${_destController.text}";
      _updateMarkers();
    });

    final firstInstr = _parseInstruction(steps[0]['html_instructions']);
    // Filter html tags from TTS
    widget.ttsService.speak("Starting navigation. $firstInstr");
    _currentInstruction = firstInstr; // Update UI with clean text

    // Camera follow
    _ignoreNextCameraMove = true;
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentLocation!, zoom: 18, tilt: 45, bearing: 0)
    ));

    // 4. Start Tracking
    if (_positionStream == null) {
       _startLiveTracking(decodedPoints);
    }
  }

  void _startLiveTracking(List<LatLng> routePath) {
    _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation, 
            distanceFilter: 5 // Ignore jitter < 5m
        )
    ).listen((Position position) {
        final newLoc = LatLng(position.latitude, position.longitude);
        
        if (mounted) {
            setState(() {
                _currentLocation = newLoc;
                _updateMarkers();
            });
            
            // Follow User (only if not manually panning)
            if (!_manualCameraMove) {
              _ignoreNextCameraMove = true;
              _mapController?.animateCamera(CameraUpdate.newCameraPosition(
                  CameraPosition(
                      target: newLoc, 
                      zoom: 18, 
                      tilt: 45,
                      bearing: position.heading // Rotate map with user heading
                  )
              ));
            }
            
            _checkProgress(newLoc, routePath);
        }
    });
  }

  void _checkProgress(LatLng currentLoc, List<LatLng> routePath) {
    if (_isRecalculating || _polylines.isEmpty || _lastRouteCalculationPoint == null) return;

    // 0. Only check for deviation if we've moved significantly from where the route was last calculated
    // This prevents recalculation loops when stationary but slightly off-road.
    final distFromStart = Geolocator.distanceBetween(
        currentLoc.latitude, currentLoc.longitude,
        _lastRouteCalculationPoint!.latitude, _lastRouteCalculationPoint!.longitude
    );
    
    if (distFromStart < _minMovementForReroute) {
        // We haven't moved enough to justify a reroute even if we look "off route"
        return;
    }

    // 1. Check for Deviation (Simple check against polyline points)
    // Note: For production, need robust point-to-segment distance. 
    // Here we check min distance to ANY point on route > threshold
    if (_isOffRoute(currentLoc, routePath)) {
        _recalculateRoute(currentLoc);
        return;
    }

    if (_steps.isEmpty || _currentStepIndex >= _steps.length) {
       _finishNavigation();
       return;
    }

    // Check distance to end of current step
    final currentStep = _steps[_currentStepIndex];
    final endLoc = currentStep['end_location'];
    final endLatLng = LatLng(endLoc['lat'], endLoc['lng']);
    
    final distance = Geolocator.distanceBetween(
        currentLoc.latitude, currentLoc.longitude, 
        endLatLng.latitude, endLatLng.longitude
    );
    
    if (distance < _voiceTriggerDistance) {
       // Announce next step
       if (_currentStepIndex + 1 < _steps.length) {
          final nextStep = _steps[_currentStepIndex + 1];
          final rawInstr = nextStep['html_instructions'];
          final instruction = _parseInstruction(rawInstr);
          
          if (_currentInstruction != instruction) { 
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
  
  bool _isOffRoute(LatLng currentPos, List<LatLng> routePath) {
      if (routePath.isEmpty) return false;
      
      // Check distance to closest POINT on polyline (Approx for speed)
      double minDistance = double.infinity;
      
      for (var p in routePath) {
          final d = Geolocator.distanceBetween(
              currentPos.latitude, currentPos.longitude, 
              p.latitude, p.longitude
          );
          if (d < minDistance) minDistance = d;
          if (minDistance < _rerouteThreshold) return false;
      }
      
      print("🔀 Deviation Detected! Min Distance to route: ${minDistance.toStringAsFixed(2)}m (Threshold: $_rerouteThreshold m)");
      return minDistance > _rerouteThreshold;
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
      final overviewPolyline = route['overview_polyline']['points'];
      final steps = route['legs'][0]['steps'] as List;
      final decodedPoints = _navService.decodePolyline(overviewPolyline);

      if (mounted) {
        setState(() {
          _polylines = {
              Polyline(
                  polylineId: const PolylineId("route"),
                  points: decodedPoints,
                  color: Colors.blue,
                  width: 5
              )
          };
          _steps = steps;
          _currentStepIndex = 0;
          _lastRouteCalculationPoint = currentLoc;
          _isRecalculating = false;
        });
        
        // Update live tracking with new path reference
        _positionStream?.cancel();
        _startLiveTracking(decodedPoints); // Restart stream with new path check

        if (steps.isNotEmpty) {
           final firstInstr = _parseInstruction(steps[0]['html_instructions']);
           widget.ttsService.speak("New route found. $firstInstr");
           setState(() => _currentInstruction = firstInstr);
        }
      }
  }

  void _finishNavigation() {
     _isNavigating = false;
     _manualCameraMove = false;
     _positionStream?.cancel();
     _positionStream = null;
     
     // Clear Persistence
     _navBox?.delete('dest_lat');
     _navBox?.delete('dest_lon');
     _navBox?.delete('dest_name');

     widget.ttsService.speak("Navigation stopped.");
     
     setState(() {
       _currentInstruction = "Navigation Stopped";
       _polylines = {};
       _destController.clear();
       _destinationLocation = null;
       
       // Zoom out to see location
       _mapController?.animateCamera(CameraUpdate.newCameraPosition(
           CameraPosition(target: _currentLocation ?? const LatLng(0,0), zoom: 15)
       ));
     });
  }

  void _updateMarkers() {
      _markers.clear();
      if (_currentLocation != null) {
          _markers.add(Marker(
              markerId: const MarkerId("current"),
              position: _currentLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
              infoWindow: const InfoWindow(title: "You")
          ));
      }
      if (_destinationLocation != null) {
          _markers.add(Marker(
              markerId: const MarkerId("dest"),
              position: _destinationLocation!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: "Destination")
          ));
      }
  }

  // Remove HTML tags from Google instructions
  String _parseInstruction(String htmlText) {
      RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
      return htmlText.replaceAll(exp, '');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Turn-by-Turn Navigation"), 
        backgroundColor: Colors.black,
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
                         displayStringForOption: (Map<String, dynamic> option) => option['description'] ?? '',
                         onSelected: (Map<String, dynamic> selection) async {
                            final placeId = selection['place_id'];
                            
                            // Get Coords from details
                            final coords = await _navService.getPlaceDetails(placeId);
                            
                            if (coords != null) {
                                setState(() {
                                   _destinationLocation = coords;
                                   _destController.text = selection['description'];
                                   _updateMarkers();
                                 });
                                 // Focus map on destination briefly
                                 _ignoreNextCameraMove = true;
                                 _mapController?.animateCamera(CameraUpdate.newLatLng(coords));
                             }
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
                                  width: MediaQuery.of(context).size.width - 32, 
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option['description'] ?? ''),
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
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                            target: _currentLocation!,
                            zoom: 15
                        ),
                        onMapCreated: (GoogleMapController controller) {
                            _mapController = controller;
                        },
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: true, // Native blue dot
                        myLocationButtonEnabled: true,
                        mapType: MapType.normal,
                        zoomControlsEnabled: true,
                        rotateGesturesEnabled: true,
                        scrollGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        zoomGesturesEnabled: true,
                        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>[
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        ].toSet(),
                        onCameraMoveStarted: () {
                          if (_ignoreNextCameraMove) {
                            _ignoreNextCameraMove = false;
                            return;
                          }
                          setState(() {
                            _manualCameraMove = true;
                          });
                        },
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
            
            // Re-center Button
            if (_manualCameraMove)
             Positioned(
                bottom: 120, // Above instruction overlay
                right: 20,
                child: FloatingActionButton(
                   heroTag: "recenter",
                   backgroundColor: Colors.white,
                   mini: true,
                   child: const Icon(Icons.my_location, color: Colors.blue),
                   onPressed: () {
                      setState(() {
                        _manualCameraMove = false;
                      });
                      if (_currentLocation != null) {
                        _ignoreNextCameraMove = true;
                        _mapController?.animateCamera(CameraUpdate.newCameraPosition(
                          CameraPosition(target: _currentLocation!, zoom: 18, tilt: 45)
                        ));
                      }
                   },
                ),
             ),

            // X Button Overlay 
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
