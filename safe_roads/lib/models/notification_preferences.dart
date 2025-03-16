import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

class NotificationPreferences with ChangeNotifier {

  StreamSubscription<RemoteMessage>? _messageSubscription;

  StreamSubscription<RemoteMessage>? get messageSubscription => _messageSubscription;

  void updateMessageSubscription(StreamSubscription<RemoteMessage> newValue){
    _messageSubscription = newValue;
    notifyListeners();
  }
}
