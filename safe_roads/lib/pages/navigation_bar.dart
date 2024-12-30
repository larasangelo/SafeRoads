import 'package:flutter/material.dart';
import 'package:safe_roads/main.dart';
import 'package:safe_roads/pages/about.dart';
import 'package:safe_roads/pages/home.dart';
import 'package:safe_roads/pages/profile.dart';

class NavigationBarExample extends StatefulWidget {
  const NavigationBarExample({Key? key}) : super(key: key);

  @override
  State<NavigationBarExample> createState() => NavigationBarExampleState();
}

class NavigationBarExampleState extends State<NavigationBarExample> {
  int _selectedIndex = 1; // Default to Home page
  bool _showNavigationBar = true; // Track visibility of navigation bar

  // List of pages
  final List<Widget> _pages = [
    const About(),
    MapPage(), // Assuming MapPage is the second page in your navigation
    const Profile(),
  ];

  // Handle tab change
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Toggle navigation bar visibility
  void toggleNavigationBar(bool show) {
    setState(() {
      _showNavigationBar = show;
    });
  }
  
  @override
  void dispose() {
    // Show the navigation bar when exiting the page
    navigationBarKey.currentState?.toggleNavigationBar(true);
    super.dispose(); // Call to dispose the widget
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex], // Display the selected page
      bottomNavigationBar: _showNavigationBar
          ? NavigationBar(
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedIndex, // Highlight the selected tab
              onDestinationSelected: _onItemTapped, // Update the selected index
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
          : null, // Hide navigation bar when _showNavigationBar is false
    );
  }
}
