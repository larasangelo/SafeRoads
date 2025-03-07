import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

class Notifications {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? fcmToken;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final AndroidInitializationSettings androidInitializationSettings = const AndroidInitializationSettings('@mipmap/ic_launcher');

  // Callback function for navigation
  VoidCallback? onSwitchRoute;
  VoidCallback? ignoreSwitchRoute;

  StreamSubscription<RemoteMessage>? _messageSubscription;

  Future<void> setupFirebaseMessaging() async {
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print("Notification permission granted");
      fcmToken = await FirebaseMessaging.instance.getToken();
      print("FCM Token: $fcmToken");

      // Prevent multiple listeners
      _messageSubscription?.cancel();
      _messageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Foreground message received: ${message.notification?.title}");
        showForegroundNotification(message);
      });
    } else {
      print("Notification permission denied");
    }
  }

  Future<void> setupNotificationChannels() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'channel_id_1', // id
      'High Importance Notifications', // name
      description: 'Channel for default notifications',
      importance: Importance.high,
      playSound: true,
      // sound: RawResourceAndroidNotificationSound('notification'), // Ensure this matches a file in res/raw
    );

    // Firebase local notification plugin
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    //Firebase messaging
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }
  
  void showForegroundNotification(RemoteMessage message) {
    if (message.notification != null) {
      flutterLocalNotificationsPlugin.show(
        0,
        message.notification!.title,
        message.notification!.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'channel_id_1', // Must match the channel ID
            'Default Notifications',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );

      bool showButton = message.data['button'] == 'true'; 
      bool changeRoute = message.data['changeRoute'] == 'true';

      if (scaffoldMessengerKey.currentContext == null) {
        print("Warning: No valid context available for overlay.");
        return;
      }

      late OverlayEntry overlayEntry;
      bool isInteracted = false; // Track if user interacted

      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: MediaQuery.of(context).size.height * 0.4, 
          left: MediaQuery.of(context).size.width * 0.1,
          right: MediaQuery.of(context).size.width * 0.1,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.0),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10.0,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.notification!.title ?? 'Notification',
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    message.notification!.body ?? '',
                    style: const TextStyle(fontSize: 16.0),
                    textAlign: TextAlign.center,
                  ),
                  if (showButton)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            isInteracted = true;
                            if (onSwitchRoute != null) {
                              onSwitchRoute!();
                            }
                            overlayEntry.remove();
                          },
                          child: const Text("Re-route", style: TextStyle(fontSize: 18.0)),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            isInteracted = true;
                            if (ignoreSwitchRoute != null) {
                              ignoreSwitchRoute!();
                            }
                            overlayEntry.remove();
                          },
                          child: const Text("Ignore", style: TextStyle(fontSize: 18.0)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final overlay = Overlay.of(scaffoldMessengerKey.currentContext!);

      if (overlay != null) {
        overlay.insert(overlayEntry);

        Future.delayed(const Duration(seconds: 5), () {
          overlayEntry.remove();    //TODO TESTAR ASSIM
          if (!isInteracted) {
            // Perform action based on changeRoute flag
            if (changeRoute && onSwitchRoute != null) {
              onSwitchRoute!();
            } else if (!changeRoute && ignoreSwitchRoute != null) {
              ignoreSwitchRoute!();
            }
          }
        });
      } else {
        print("Warning: Overlay is null, skipping notification display.");
      }
    }
  }
}

