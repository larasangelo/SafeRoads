import 'package:flutter/material.dart';

class UserPreferences with ChangeNotifier {
  bool _reRoute = false;  // Ensure it's non-null

  bool get reRoute => _reRoute;

  void updateReRoute(bool newValue) {
    _reRoute = newValue;
    notifyListeners();
  }
}
