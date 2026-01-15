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
  static const double _freeFallThreshold = 2.5; // ~0.25g (Lowered to be stricter)
  
  // 2. Impact: Hitting the ground (Minimum 3g for a real fall impact)
  static const double _impactThreshold = 30.0; 
  
  // 3. Stillness: Laying on ground (Must be near 1g)
  static const double _gravityThresholdLo = 8.5;  // ~0.85g
  static const double _gravityThresholdHi = 11.5; // ~1.15g
  
  bool _possibleFallDetected = false;
  bool _freeFallDetected = false;
  DateTime? _freeFallTime;
  
  int _consecutiveStillSamples = 0;
  static const int _requiredStillSamples = 15; // At 20Hz, this is ~0.75s of continuous stillness
  
  Timer? _fallConfirmationTimer;
  double _lastMagnitude = 9.8;

  SosService(this._contactService, this._ttsService);

  void initialize(Function onFallDetected) {
    _onFallDetected = onFallDetected;
  }

  void startMonitoring() {
    if (_isMonitoring) return;
    
    // Most devices update at ~20-50Hz
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      _lastMagnitude = magnitude;

      if (!_possibleFallDetected) {
         // Step 1: Detect Free Fall (Weightlessness)
         // True free fall is < 1.0, but we allow 2.5 for tumbling/soft drops
         if (magnitude < _freeFallThreshold) {
             _freeFallDetected = true;
             _freeFallTime = DateTime.now();
         }
         
         // Step 2: Detect Impact shortly after Free Fall
         bool freeFallRecent = _freeFallDetected && 
            _freeFallTime != null && 
            DateTime.now().difference(_freeFallTime!).inMilliseconds < 800;

         if (magnitude > _impactThreshold) {
             if (freeFallRecent || magnitude > 45.0) { // High threshold (4.5g) for trip/fall without clear free fall
                 _possibleFallDetected = true;
                 _freeFallDetected = false;
                 _consecutiveStillSamples = 0;
                 
                 // Wait a moment for the phone to settle after impact before checking stillness
                 _fallConfirmationTimer?.cancel();
                 _fallConfirmationTimer = Timer(const Duration(milliseconds: 1500), () {
                     // The actual check logic is moved into the stream listener
                     // to ensure continuous stillness is monitored
                 });
             }
         }
      } else {
          // Step 3: Verify Stillness (Post-Impact)
          // If the user is walking, the magnitude will fluctuate. 
          // If fallen, the phone is resting near 9.8.
          if (_fallConfirmationTimer != null && !_fallConfirmationTimer!.isActive) {
              if (magnitude >= _gravityThresholdLo && magnitude <= _gravityThresholdHi) {
                  _consecutiveStillSamples++;
                  if (_consecutiveStillSamples >= _requiredStillSamples) {
                      _triggerFall();
                  }
              } else {
                  // Movement detected during the "stillness" phase, likely a false positive (walking/running)
                  _possibleFallDetected = false;
                  _consecutiveStillSamples = 0;
              }
          }
      }
    });
    _isMonitoring = true;
  }

  void stopMonitoring() {
    _accelSubscription?.cancel();
    _fallConfirmationTimer?.cancel();
    _isMonitoring = false;
    _possibleFallDetected = false;
    _consecutiveStillSamples = 0;
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
