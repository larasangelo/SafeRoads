import 'package:flutter/material.dart';

class NavigationBarVisibility extends ChangeNotifier {
  bool _isVisible = true; // Initial state

  bool get isVisible => _isVisible;

  void setVisibility(bool show) {
    if (_isVisible != show) {
      _isVisible = show;
      notifyListeners();
    }
  }
}