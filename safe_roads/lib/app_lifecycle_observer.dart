import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:safe_roads/log_service.dart';
import 'package:safe_roads/session_manager.dart';

class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        Future.microtask(() async {
          final logService = LogService();
          await logService.logAppStartEvent(); 
          await SessionManager().ensureSessionStarted(logService);
          final sessionId = SessionManager().sessionId;
          SessionManager().sessionId = sessionId;
        });
      }
    }
  }
}
