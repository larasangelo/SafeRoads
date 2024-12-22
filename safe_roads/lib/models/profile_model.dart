import 'package:firebase_auth/firebase_auth.dart';


class ProfileModel {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Update user profile
  Future<void> updateUser({
    required String email,
    required String username,
  }) async {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    try {
      if (username.isNotEmpty) {
        await user.updateDisplayName(username);
      }

      await user.reload();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "Failed to update user.");
    }
  }
}
