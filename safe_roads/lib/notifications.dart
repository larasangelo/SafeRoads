import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class Notifications {
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String? fcmToken;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final AndroidInitializationSettings androidInitializationSettings = const AndroidInitializationSettings('@mipmap/ic_launcher');

  Future<void> setupFirebaseMessaging() async {
    // Request permissions
    NotificationSettings settings = await FirebaseMessaging.instance
        .requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print("Notification permission granted");
      fcmToken = await FirebaseMessaging.instance.getToken();
      print("FCM Token: $fcmToken");
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Foreground message received: ${message.notification?.title}");
        showForegroundNotification(message);
      });
    } else {
      print("Notification permission denied");
    }
  }

  Future<void> setupNotificationChannels() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
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
            'default_channel_id', // Must match the channel ID
            'Default Notifications',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            icon: '@mipmap/ic_launcher',
            // sound: RawResourceAndroidNotificationSound('notification'), // Ensure this matches your file in res/raw
          ),
        ),
      );
      // Create the overlay entry
      OverlayEntry overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: MediaQuery.of(context).size.height * 0.4, // Centered vertically
          left: MediaQuery.of(context).size.width * 0.1, // Add some margin
          right: MediaQuery.of(context).size.width * 0.1, // Add some margin
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
                    style: const TextStyle(
                      fontSize: 16.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Access the Overlay using the current context
      final overlay = Overlay.of(scaffoldMessengerKey.currentContext!);

      // Insert the overlay entry into the overlay
      overlay.insert(overlayEntry);

      // Remove the overlay entry after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        overlayEntry.remove();
      });
        }
  }



}

