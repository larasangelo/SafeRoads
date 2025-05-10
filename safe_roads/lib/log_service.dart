import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class LogService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<String> startSession() async {
    final user = _auth.currentUser;
    if (user == null) return '';
    final sessionRef = _db.child('userLogs').child(user.uid).child('sessions').push();

    await sessionRef.set({
      'startTime': DateTime.now().toIso8601String(),
      'routeChosen': null,
      'routeWasAdjusted': null,
      'reRoutePromptShown': false,
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
}