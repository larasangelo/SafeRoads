import 'package:flutter/material.dart';
import 'package:safe_roads/pages/about.dart';
import 'package:safe_roads/pages/home.dart';
import 'package:safe_roads/pages/profile.dart';


class NavigationBarExample extends StatefulWidget {
  const NavigationBarExample({Key? key}) : super(key: key);

  @override
  State<NavigationBarExample> createState() => _NavigationBarExampleState();
}

class _NavigationBarExampleState extends State<NavigationBarExample> {
  int _selectedIndex = 1; // Default to Home page

  // List of pages
  final List<Widget> _pages = [
    const About(),
    const MapPage(),
    const Profile(),
  ];

  // Handle tab change
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex], // Display the selected page
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _selectedIndex, // Highlight the selected tab
        onDestinationSelected: _onItemTapped, // Update the selected index
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.info_outline),
            label: "About",
          ),
          NavigationDestination(
            icon: Icon(Icons.home),
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
        backgroundColor: Colors.white, // Navigation bar background
        elevation: 3, // Subtle shadow effect
      ),
    );
  }
}
