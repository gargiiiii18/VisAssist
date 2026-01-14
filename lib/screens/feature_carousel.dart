import 'package:flutter/material.dart';
import '../main.dart';
import 'contacts_page.dart';
import 'face_recognition_screen.dart';
import 'navigation_screen.dart';
import '../services/contact_service.dart';
import '../services/tts_service.dart';
import '../services/face_storage_service.dart';
import '../services/face_recognition_service.dart';

// Since VisionHomePage is in main.dart, we might have circular imports if main imports this.
// To avoid this, we should really move VisionHomePage to `lib/screens/vision_home_page.dart`.
// But to minimize breakage, I will define FeatureCarousel here and assume VisionHomePage is available 
// or I will move VisionHomePage content to a new file in next step.
// Let's create FeatureCarousel accepting the pages as children or builders.

class FeatureCarousel extends StatefulWidget {
  final ContactService contactService;
  final TTSService ttsService;
  final FaceStorageService faceStorage;
  final FaceRecognitionService faceRecognition;

  const FeatureCarousel({
    super.key,
    required this.contactService,
    required this.ttsService,
    required this.faceStorage,
    required this.faceRecognition,
  });

  @override
  State<FeatureCarousel> createState() => _FeatureCarouselState();
}

class _FeatureCarouselState extends State<FeatureCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  int? _targetPage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
          
          // Only speak if we reached the target page OR if it's a swipe (no targetPage set)
          if (_targetPage == null || _targetPage == index) {
            String pageName;
            switch (index) {
              case 0:
                pageName = "Vision Mode";
                break;
              case 1:
                pageName = "Emergency Contacts";
                break;
              case 2:
                pageName = "Face Recognition";
                break;
              case 3:
                pageName = "Navigation Mode";
                break;
              default:
                pageName = "";
            }
            if (pageName.isNotEmpty) {
              widget.ttsService.speak(pageName);
            }
            _targetPage = null; // Reset target
          }
        },
        children: [
          VisionHomePage(isActive: _currentPage == 0),
          ContactsPage(
            contactService: widget.contactService,
            ttsService: widget.ttsService,
          ),
          FaceRecognitionScreen(
            faceRecognition: widget.faceRecognition,
            faceStorage: widget.faceStorage,
            ttsService: widget.ttsService,
            isActive: _currentPage == 2,
          ),
          NavigationScreen(ttsService: widget.ttsService),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentPage,
        type: BottomNavigationBarType.fixed, // Needed for 4+ items
        onTap: (index) {
            if (_currentPage == index) return;
            
            _targetPage = index;
            _pageController.animateToPage(
                index, 
                duration: const Duration(milliseconds: 300), 
                curve: Curves.easeInOut
            );
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Vision"),
          BottomNavigationBarItem(icon: Icon(Icons.perm_contact_calendar), label: "Contacts"),
          BottomNavigationBarItem(icon: Icon(Icons.face), label: "Faces"),
          BottomNavigationBarItem(icon: Icon(Icons.navigation), label: "Nav"),
        ],
      ),
    );
  }
}
