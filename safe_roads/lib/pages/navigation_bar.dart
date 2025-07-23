// pages/navigation_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for SystemNavigator.pop()
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'package:safe_roads/models/navigation_bar_visibility.dart';
// import 'package:safe_roads/configuration/navigation_bar_config.dart'; // REMOVE THIS IMPORT
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
  int _selectedIndex = 1;

  late PageController _pageController;
  final PageStorageBucket _bucket = PageStorageBucket();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // New method to show the exit confirmation dialog
  Future<bool> _showExitConfirmationDialog() async {
    return await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(LanguageConfig.getLocalizedString(
            Provider.of<UserPreferences>(context).languageCode, 'exitAppTitle')),
        content: Text(LanguageConfig.getLocalizedString(
            Provider.of<UserPreferences>(context).languageCode, 'exitAppMessage')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), 
            child: Text(LanguageConfig.getLocalizedString(
                Provider.of<UserPreferences>(context).languageCode, 'no')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), 
            child: Text(LanguageConfig.getLocalizedString(
                Provider.of<UserPreferences>(context).languageCode, 'yes')),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _handlePopAction() async {
    // If the current page is the "Home" page (MapPage at index 1)
    if (_selectedIndex == 1) {
      // Show confirmation dialog
      final bool? shouldExit = await _showExitConfirmationDialog();
      if (shouldExit == true) {
        // If user confirms, exit the app
        SystemNavigator.pop();
      }
      // If user cancels, do nothing (stay on MapPage)
    } else {
      // If we are not on the "Home" page, navigate to the "Home" page.
      _pageController.jumpToPage(1); // Navigate to the MapPage (Home)
    }
  }

 @override
  Widget build(BuildContext context) {
    String languageCode = Provider.of<UserPreferences>(context).languageCode;
    // Listen to the NavigationBarVisibility provider
    final navigationBarVisibility = Provider.of<NavigationBarVisibility>(context);
    bool _showNavigationBar = navigationBarVisibility.isVisible; // Get state from provider

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) {
          return;
        }
        await _handlePopAction();
      },
      child: Scaffold(
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
              child: const MapPage(),
            ),
            const Profile(),
          ],
        ),
        bottomNavigationBar: _showNavigationBar // Use the state from the provider
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
                elevation: 3,
              )
            : null,
      ),
    );
  }
}