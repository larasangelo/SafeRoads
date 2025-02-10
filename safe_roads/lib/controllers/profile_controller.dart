import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:safe_roads/models/profile_model.dart';
import 'package:safe_roads/repositories/user_profile_repository.dart';

class ProfileController {
  final UserProfileRepository _userProfileRepository = UserProfileRepository();
  final ProfileModel _profileModel = ProfileModel();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Fetch user profile
  Future<Map<String, dynamic>> fetchUserProfile() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    try {
      final data = await _userProfileRepository.fetchUserProfile(user.uid);
      // print(data);
      return {
        're_route': data['re_route'] ?? true,
        'tolls': data['tolls'] ?? false,
        'measure': data['measure'] ?? "km",
        'username': data['username'] ?? "Unknown",
        'country': data['location'] ?? "Unknown",
        'email': data['email'] ?? user.email ?? "Unknown",
        'level': data['level'] ?? 1,
        'distance': data['distance'] ?? 0,
        'targetDistance': data['targetDistance'] ?? 200,
        'totalKm': data['totalKm'] ?? 0,
        'places': data['places'] ?? 0,
        'avatar': data['avatar'] ?? "assets/profile_images/avatar_1.jpg"
      };
    } catch (e) {
      throw Exception("Failed to fetch user profile: $e");
    }
  }

  // Update a user's profile
  Future<void> updateUser({
    required BuildContext context,
    required String username,
    required String email,
    required String country, 
    required String avatar,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;

    // print("username: $username");
    // print("email: $email");
    // print("country: $country");
    // print("avatar: $avatar");

    if (user == null) {
     _showErrorDialog(context, "No user is currently signed in.");
      return;
    }

    if (username.isEmpty || email.isEmpty || country.isEmpty) {
     _showErrorDialog(context, "All fields are required.");
      return;
    }

    try {
      // Update the user's authentication details
      await _profileModel.updateUser(email: email, username: username);

      // Update the user's profile in the database
      await _userProfileRepository.updateUserProfile(user.uid, {
        'username': username,
        'email': email,
        'location': country,
        'avatar': avatar
      });

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully!")),
      );
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  Future<void> updateUserPreference({
    required BuildContext context,
    required String key,
    required dynamic value,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
     _showErrorDialog(context, "No user is currently signed in.");
      return;
    }

    try {
      // Update the user's profile in the database
      await _userProfileRepository.updateUserProfile(user.uid, {
        key: value,
      });

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully!")),
      );
    } catch (e) {
      _showErrorDialog(context, e.toString());
    }
  }

  Future<void> reauthenticate(String currentPassword) async {
    final user = FirebaseAuth.instance.currentUser;
    final cred = EmailAuthProvider.credential(
      email: user!.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    await reauthenticate(currentPassword);
    await FirebaseAuth.instance.currentUser!.updatePassword(newPassword);
  }

  Future<void> deleteUserAccount({
    required BuildContext context,
    required String password,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showErrorDialog(context, "No user is currently signed in.");
      return;
    }

    try {
      // Re-authenticate the user
      final cred = EmailAuthProvider.credential(email: user.email!, password: password);
      await user.reauthenticateWithCredential(cred);

      // Delete user data from Realtime Database
      await _userProfileRepository.deleteUserProfile(user.uid);

      // Delete the account
      await user.delete();

      // Navigate the user to the login screen
      Navigator.pushReplacementNamed(context, '/login');

      // Show success feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account deleted successfully.")),
      );
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
