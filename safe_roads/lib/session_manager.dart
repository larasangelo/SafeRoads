import 'package:safe_roads/log_service.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  String? sessionId;
  String? destinationId;

  factory SessionManager() => _instance;

  SessionManager._internal();

  Future<void> ensureSessionStarted(LogService logService) async {
    sessionId ??= await logService.startSession();
  }

  void reset() {
    sessionId = null;
    destinationId = null;
  }

}
