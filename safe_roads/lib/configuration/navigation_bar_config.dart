import 'package:flutter/material.dart';

class NavigationBarConfig {
  static int selectedIndex = 1; // Default to the MapPage
  static bool showNavigationBar = true; // Track visibility of navigation bar
  static PageController pageController = PageController(initialPage: 1);
  static PageStorageBucket bucket = PageStorageBucket(); 
}