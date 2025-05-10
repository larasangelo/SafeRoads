import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class LogService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> _ensureUserMetadata() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final userRef = _db.child('userLogs').child(user.uid);

    final snapshot = await userRef.once();
    if (!snapshot.snapshot.exists) {
      await userRef.update({
        'userEmail': user.email,
      });
    }
  }

  Future<String> startSession() async {
    final user = _auth.currentUser;
    if (user == null) return '';

    await _ensureUserMetadata();

    final sessionRef = _db.child('userLogs').child(user.uid).child('sessions').push();

    await sessionRef.set({
      'startTime': DateTime.now().toIso8601String(),
      'routeChosen': null,
      'routeWasAdjusted': null,
      'reRoutePromptShown': null,
      'reRouteAction': null,
    });

    return sessionRef.key ?? '';
  }

  Future<void> updateSession(String sessionId, Map<String, dynamic> updates) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final sessionRef = _db.child('userLogs').child(user.uid).child('sessions').child(sessionId);
    await sessionRef.update(updates);
  }

  Future<void> logDestination({
    required String sessionId,
    required Map<String, dynamic> destinationData,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final destinationsRef = _db
        .child('userLogs')
        .child(user.uid)
        .child('sessions')
        .child(sessionId)
        .child('destinations')
        .push();

    await destinationsRef.set(destinationData);
  }
}