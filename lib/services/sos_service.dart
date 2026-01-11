import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'contact_service.dart';
import 'tts_service.dart';

class SosService {
  final ContactService _contactService;
  final TTSService _ttsService;
  static const platform = MethodChannel('com.example.fyp_app/sms');

  StreamSubscription? _accelSubscription;
  bool _isMonitoring = false;
  Function? _onFallDetected;
  
  // Fall Detection Parameters
  // 1. Free Fall: Phone dropping (near 0g)
  static const double _freeFallThreshold = 3.0; // ~0.3g
  
  // 2. Impact: Hitting the ground
  //    Lowered to 20.0 (~2g) because soft surfaces absorb energy.
  //    However, to prevent false positives from jumps/shakes, we require Free Fall First.
  static const double _impactThreshold = 20.0; 
  
  // 3. Stillness: Laying on ground
  static const double _gravityThresholdLo = 5.0;  // ~0.5g
  static const double _gravityThresholdHi = 15.0; // ~1.5g
  
  bool _possibleFallDetected = false;
  bool _freeFallDetected = false;
  DateTime? _freeFallTime;
  
  Timer? _fallConfirmationTimer;
  double _lastMagnitude = 9.8;

  SosService(this._contactService, this._ttsService);

  void initialize(Function onFallDetected) {
    _onFallDetected = onFallDetected;
  }

  void startMonitoring() {
    if (_isMonitoring) return;
    
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _lastMagnitude = magnitude;

      // NEW: soft free-fall check for short/soft drops
      bool freeFallLike = magnitude < 6.0;

      if (!_possibleFallDetected) {
         // Check for Free Fall (Precursor)
         if (magnitude < _freeFallThreshold || freeFallLike) {
             _freeFallDetected = true;
             _freeFallTime = DateTime.now();
             // print("Free Fall Detected ($magnitude)");
         }
         
         // Check if Free Fall was recent (within 0.5s)
         bool freeFallRecent = _freeFallDetected && 
            _freeFallTime != null && 
            DateTime.now().difference(_freeFallTime!).inMilliseconds < 1000;

         // Check for Impact
         if (magnitude > _impactThreshold) {
             // If impact happens shortly after free fall, it's very likely a drop
             if (freeFallRecent) {
                 _possibleFallDetected = true;
                 _freeFallDetected = false; // Reset
                 // print(">>> IMPACT DETECTED ($magnitude) AFTER FREE FALL. Check Stability...");
                 
                 _fallConfirmationTimer?.cancel();
                 _fallConfirmationTimer = Timer(const Duration(seconds: 3), () {
                     _checkFinalStability();
                 });
             } else if (magnitude > 35.0) { 
                 // Super hard impact (3.5g) triggers detection even without free fall (e.g. running trip)
                 _possibleFallDetected = true;
                  // print(">>> HARD IMPACT ($magnitude). Check Stability...");
                 _fallConfirmationTimer?.cancel();
                 _fallConfirmationTimer = Timer(const Duration(seconds: 3), () {
                     _checkFinalStability();
                 });
             }
         }
      }
    });
    _isMonitoring = true;
  }

  void _checkFinalStability() {
      // Step 3: Check if the phone is now relatively still (near 1g)
      // If the user is running, magnitude will likely fluctuate or be high.
      // If fallen, it should be resting (~9.8).
      
      if (_lastMagnitude >= _gravityThresholdLo && _lastMagnitude <= _gravityThresholdHi) {
          // Confirmed Fall
          _triggerFall();
      } else {
          // print(">>> False Alarm: Phone is still moving or orientation invalid ($_lastMagnitude)");
          _possibleFallDetected = false; 
      }
  }

  void stopMonitoring() {
    _accelSubscription?.cancel();
    _fallConfirmationTimer?.cancel();
    _isMonitoring = false;
    _possibleFallDetected = false;
  }

  void _triggerFall() {
    // print(">>> FALL CONFIRMED!");
    stopMonitoring(); 
    if (_onFallDetected != null) {
      _onFallDetected!();
    }
  }

  /// Sends the actual SOS.
  Future<void> sendSos() async {
    // 1. Get Location
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      print("Location error: $e");
    }

    String mapLink = position != null 
        ? "https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}"
        : "Unknown Location";

    String message = "SOS! I have detected a fall/emergency. Help needed. Location: $mapLink";

    // 2. Get Contacts
    final contacts = _contactService.getContacts();
    if (contacts.isEmpty) {
      await _ttsService.speak("No emergency contacts saved. Cannot send alert.");
      return;
    }

    // 3. Send SMS via Native Channel
    for (var contact in contacts) {
      String number = contact['number'];
      try {
        await platform.invokeMethod('sendSMS', <String, dynamic>{
          'number': number,
          'message': message,
        });
        print("Sent SMS to $number");
      } catch (e) {
        print("SMS Error to $number: $e");
      }
    }

    await _ttsService.speak("SOS Alerts sent.");
    
    // Resume monitoring after a delay
    Future.delayed(const Duration(seconds: 10), () {
        startMonitoring();
    });
  }
  
  void resumeMonitoring() {
      startMonitoring();
  }
}
