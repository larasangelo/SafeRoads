import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class LogService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> _ensureUserMetadata() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final emailRef = _db.child('userLogs').child(user.uid).child('userEmail');
    final snapshot = await emailRef.once();

    if (!snapshot.snapshot.exists) {
      await emailRef.set(user.email);
    }
  }

  Future<String> startSession() async {
    final user = _auth.currentUser;
    if (user == null) return '';

    await _ensureUserMetadata();

    final sessionRef = _db.child('userLogs').child(user.uid).child('sessions').push();

    await sessionRef.set({
      'startTime': DateTime.now().toIso8601String(),
    });

    return sessionRef.key ?? '';
  }

  Future<void> logAppStartEvent() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final appStartRef = _db
        .child('userLogs')
        .child(user.uid)
        .child('appStarts')
        .push();

    await appStartRef.set({
      'timestamp': DateTime.now().toIso8601String(),
    });
  }


  Future<void> updateSession(String sessionId, Map<String, dynamic> updates) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final sessionRef = _db.child('userLogs').child(user.uid).child('sessions').child(sessionId);
    await sessionRef.update(updates);
  }

  Future<String?> logDestination({
    required String sessionId,
    required Map<String, dynamic> destinationData,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final destinationsRef = _db
        .child('userLogs')
        .child(user.uid)
        .child('sessions')
        .child(sessionId)
        .child('destinations')
        .push();

    await destinationsRef.set(destinationData);
    return destinationsRef.key;
  }

  Future<void> updateDestination({
    required String sessionId,
    required String destinationId,
    required Map<String, dynamic> updates,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final destinationRef = _db
        .child('userLogs')
        .child(user.uid)
        .child('sessions')
        .child(sessionId)
        .child('destinations')
        .child(destinationId);

    await destinationRef.update(updates);
  }
}