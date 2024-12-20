import 'package:firebase_auth/firebase_auth.dart';
import 'package:safe_roads/repositories/user_profile_repository.dart';

class ProfileController {
  final UserProfileRepository _userProfileRepository = UserProfileRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Fetch user profile
  Future<Map<String, String>> fetchUserProfile() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    final data = await _userProfileRepository.fetchUserProfile(user.uid);
    return {
      'username': data['username'] ?? "Unknown",
      'country': data['location'] ?? "Unknown",
      'email': data['email'] ?? "Unknown",
    };
  }

  // Update user profile
  Future<void> updateUser({
    required String username,
    required String email,
    required String country,
  }) async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    await _userProfileRepository.updateUserProfile(user.uid, {
      'username': username,
      'email': email,
      'location': country,
    });
  }
}
