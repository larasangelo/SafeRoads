import 'package:flutter/material.dart';
import '../models/auth_model.dart';

class AuthController {
  final AuthModel _authModel = AuthModel();

  Future<void> registerUser({
    required BuildContext context,
    required String username,
    required String email,
    required String password,
    required String confirmPassword,
  }) async {
    if (username.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showErrorDialog(context, "All fields are required.");
      return;
    }

    if (password != confirmPassword) {
      _showErrorDialog(context, "Passwords do not match.");
      return;
    }

    try {
      await _authModel.registerUser(
        email: email,
        password: password,
        username: username,
      );

      // Navigate to Login page
      Navigator.pushNamed(context, '/login');
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  Future<void> loginUser({
    required BuildContext context,
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || password.isEmpty) {
      _showErrorDialog(context, "Email and Password are required.");
      return;
    }

    try {
      await _authModel.loginUser(email: email, password: password);

      // Navigate to the home page after successful login
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }
}
