import 'package:firebase_auth/firebase_auth.dart';

class ProfileModel {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> updateUser({
    required String email,
    // required String password,
    required String username,
  }) async {
    print("auth_model: $username, $email");

    final User? user = _auth.currentUser;

    if (user == null) {
      throw Exception("No user is currently signed in.");
    }

    try {
      // Update the password if provided
      // if (password.isNotEmpty) {
      //   await user.updatePassword(password);
      // }

      // Update display name
      if (username.isNotEmpty) {
        await user.updateDisplayName(username);
      }

      // Reload the user to apply changes
      await user.reload();
    } on FirebaseAuthException catch (e) {
      throw Exception(e.message ?? "Failed to update user.");
    }
  }
}
