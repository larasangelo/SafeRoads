import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/configuration/navigation_bar_config.dart';
import 'package:safe_roads/models/user_preferences.dart';
import 'package:safe_roads/pages/about.dart';
import 'package:safe_roads/pages/home.dart';
import 'package:safe_roads/pages/profile.dart';

class NavigationBarExample extends StatefulWidget {
  const NavigationBarExample({super.key});

  @override
  State<NavigationBarExample> createState() => NavigationBarExampleState();
}

class NavigationBarExampleState extends State<NavigationBarExample> {
  int _selectedIndex = NavigationBarConfig.selectedIndex;
  bool _showNavigationBar = NavigationBarConfig.showNavigationBar;
  final PageController _pageController = NavigationBarConfig.pageController;
  final PageStorageBucket _bucket = NavigationBarConfig.bucket; // For persisting state

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
    String languageCode = Provider.of<UserPreferences>(context).languageCode;
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
            child: const MapPage(), // Use PageStorage to preserve MapPage state
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
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.info_outline),
                  selectedIcon: const Icon(Icons.info),
                  label: LanguageConfig.getLocalizedString(languageCode, 'about'), 
                ),
                NavigationDestination(
                  icon: const Icon(Icons.place_outlined),
                  selectedIcon: const Icon(Icons.place),
                  label: LanguageConfig.getLocalizedString(languageCode, 'navigation'), 
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: LanguageConfig.getLocalizedString(languageCode, 'profile'),
                ),
              ],
              backgroundColor: Colors.white,
              elevation: 3,
            )
          : null,
    );
  }
}
