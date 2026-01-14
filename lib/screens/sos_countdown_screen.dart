import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../services/sos_service.dart';
import '../services/voice_control_service.dart';
import '../services/tts_service.dart';

class SosCountdownScreen extends StatefulWidget {
  final SosService sosService;
  final TTSService ttsService;
  final VoiceControlService voiceService;

  const SosCountdownScreen({
    super.key,
    required this.sosService,
    required this.ttsService,
    required this.voiceService,
  });

  @override
  State<SosCountdownScreen> createState() => _SosCountdownScreenState();
}

class _SosCountdownScreenState extends State<SosCountdownScreen> {
  int _countdown = 10;
  Timer? _timer;
  Color _bgColor = Colors.red;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _startEverything();
  }

  void _startEverything() async {
    // 1. Alert user
    if (mounted) {
      await Vibration.vibrate(pattern: [500, 500, 500, 500]);
    }
    
    // We await this speak. Because we updated TTSService to awaitSpeakCompletion(true),
    // this line will block until the speech is DONE.
    await widget.ttsService.speak("Fall detected. Sending help in 10 seconds. Say CANCEL if you are okay.");

    if (!mounted) return; // Check if user navigated away

    // 2. Start Flash
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) return;
      setState(() {
        _bgColor = _bgColor == Colors.red ? Colors.black : Colors.red;
      });
    });

    // 3. Start Listen Loop (Parallel to countdown)
    _listenForCancel();

    // 4. Start Countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      
      setState(() {
        _countdown--;
      });

      if (_countdown <= 0) {
        _sendHelp();
      } 
      // Removed voice countdown to prevent interfering with microphone listening
      // else if (_countdown <= 3) { widget.ttsService.speak("$_countdown"); }
    });
  }
  
  void _listenForCancel() async {
    // Listen efficiently for the entire duration by looping
    // If the recognizer times out early (silence), we restart it immediately.
    
    while (_countdown > 0 && mounted) {
      final duration = Duration(seconds: _countdown + 2);
      
      String? keyword = await widget.voiceService.listenForKeywords(
        ['cancel', 'okay', 'stop', 'no', 'fake', 'false'], 
        duration
      );
      
      if (!mounted) return;

      if (keyword != null && _countdown > 0) {
        // print("SOS Cancelled by voice: $keyword");
        _cancel();
        return;
      }

      // If loop restarts, add small delay to be safe preventing tight error loops
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  void _sendHelp() {
    _timer?.cancel();
    _flashTimer?.cancel();
    widget.sosService.sendSos();
    if (mounted) Navigator.pop(context);
  }

  void _cancel() {
    _timer?.cancel();
    _flashTimer?.cancel();
    widget.ttsService.speak("SOS Cancelled.");
    widget.sosService.resumeMonitoring();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 100, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              "FALL DETECTED",
              style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              "Sending SOS in $_countdown",
              style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 150,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                onPressed: _cancel,
                child: const Text(
                  "I'M OKAY\n(CANCEL)",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
