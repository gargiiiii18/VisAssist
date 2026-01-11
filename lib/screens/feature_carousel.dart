import 'package:flutter/material.dart';
import '../main.dart'; // For VisionHomePage access or move VisionHomePage to separate file if needed. 
// Assuming VisionHomePage is accessible or we will refactor.
// Ideally VisionHomePage should be in screens/.
// Checks: main.dart has VisionHomePage. We can import main.dart but better to move it later.
// For now, let's assume we pass it or import it.
import 'contacts_page.dart';
import '../services/contact_service.dart';
import '../services/tts_service.dart';

// Since VisionHomePage is in main.dart, we might have circular imports if main imports this.
// To avoid this, we should really move VisionHomePage to `lib/screens/vision_home_page.dart`.
// But to minimize breakage, I will define FeatureCarousel here and assume VisionHomePage is available 
// or I will move VisionHomePage content to a new file in next step.
// Let's create FeatureCarousel accepting the pages as children or builders.

class FeatureCarousel extends StatefulWidget {
  final Widget visionPage;
  final ContactService contactService;
  final TTSService ttsService;

  const FeatureCarousel({
    super.key,
    required this.visionPage,
    required this.contactService,
    required this.ttsService,
  });

  @override
  State<FeatureCarousel> createState() => _FeatureCarouselState();
}

class _FeatureCarouselState extends State<FeatureCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

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
          String pageName = index == 0 ? "Vision Mode" : "Emergency Contacts";
          widget.ttsService.speak(pageName);
        },
        children: [
          widget.visionPage,
          ContactsPage(
            contactService: widget.contactService,
            ttsService: widget.ttsService,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.black,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        currentIndex: _currentPage,
        onTap: (index) {
            _pageController.animateToPage(
                index, 
                duration: const Duration(milliseconds: 300), 
                curve: Curves.easeInOut
            );
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: "Vision"),
          BottomNavigationBarItem(icon: Icon(Icons.perm_contact_calendar), label: "Contacts"),
        ],
      ),
    );
  }
}
