class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  String? sessionId;

  factory SessionManager() {
    return _instance;
  }

  SessionManager._internal();
}
