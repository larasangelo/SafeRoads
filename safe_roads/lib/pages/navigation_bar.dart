import 'package:flutter/material.dart';
import 'package:safe_roads/pages/about.dart';
import 'package:safe_roads/pages/home.dart';
import 'package:safe_roads/pages/profile.dart';

class NavigationBarExample extends StatefulWidget {
  const NavigationBarExample({Key? key}) : super(key: key);

  @override
  State<NavigationBarExample> createState() => NavigationBarExampleState();
}

class NavigationBarExampleState extends State<NavigationBarExample> {
  int _selectedIndex = 1; // Default to the MapPage
  bool _showNavigationBar = true; // Track visibility of navigation bar
  final PageController _pageController = PageController(initialPage: 1);
  final PageStorageBucket _bucket = PageStorageBucket(); // For persisting state

  // Toggle navigation bar visibility
  void toggleNavigationBar(bool show) {
    setState(() {
      _showNavigationBar = show;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        children: [
          const About(),
          PageStorage(
            bucket: _bucket,
            child: MapPage(), // Use PageStorage to preserve MapPage state
          ),
          const Profile(),
        ],
      ),
      bottomNavigationBar: _showNavigationBar
          ? NavigationBar(
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                _pageController.jumpToPage(index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.info_outline),
                  selectedIcon: Icon(Icons.info),
                  label: "About",
                ),
                NavigationDestination(
                  icon: Icon(Icons.place_outlined),
                  selectedIcon: Icon(Icons.place),
                  label: "Navigation",
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: "Profile",
                ),
              ],
              backgroundColor: Colors.white,
              elevation: 3,
            )
          : null,
    );
  }
}
