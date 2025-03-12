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
      // print("changeRoute no notification: $changeRoute");

      if (scaffoldMessengerKey.currentContext == null) {
        print("Warning: No valid context available for overlay.");
        return;
      }

      late OverlayEntry overlayEntry;
      bool isInteracted = false; 

      // AnimationController for smooth progress transition
      late AnimationController _animationController;

      overlayEntry = OverlayEntry(
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              _animationController = AnimationController(
                vsync: Navigator.of(context), // Ensures smooth animations
                duration: const Duration(seconds: 5), // Full duration
              );

              _animationController.forward(); // Start animation immediately

              return Positioned(
                top: showButton
                    ? MediaQuery.of(context).size.height * 0.1
                    : MediaQuery.of(context).size.height * 0.65,
                left: MediaQuery.of(context).size.width * 0.01,
                right: MediaQuery.of(context).size.width * 0.01,
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
                          message.notification?.title ?? 'Notification',
                          style: const TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          message.notification?.body ?? '',
                          style: const TextStyle(fontSize: 16.0),
                          textAlign: TextAlign.center,
                        ),
                        if (showButton) ...[
                          // If changeRoute is true, apply animation to "Re-route" button
                          if (changeRoute)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Animated "Re-route" button
                                AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    return Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Animated Background on "Re-route"
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 120, maxHeight: 40), // Set a reasonable width
                                          child: Container(
                                            height: 50, // Match button height
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(50),
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.pinkAccent.withOpacity(0.5),
                                                  Colors.purple.withOpacity(0.9)
                                                ],
                                                stops: [
                                                  0.0,
                                                  _animationController.value
                                                ], // Progress effect from left to right
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // The actual "Re-route" button with text ABOVE the animation
                                        ElevatedButton(
                                          onPressed: () {
                                            isInteracted = true;
                                            _animationController.stop(); // Stop animation
                                            onSwitchRoute?.call();
                                            overlayEntry.remove();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent, // Let animation show through
                                            shadowColor: Colors.transparent, // Remove unwanted shadow
                                          ),
                                          child: const Text(
                                            "Re-route",
                                            style: TextStyle(
                                                fontSize: 18.0, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                // "Ignore" button
                                ElevatedButton(
                                  onPressed: () {
                                    isInteracted = true;
                                    _animationController.stop(); // Stop animation
                                    ignoreSwitchRoute?.call();
                                    overlayEntry.remove();
                                  },
                                  child: const Text("Ignore", style: TextStyle(fontSize: 18.0)),
                                ),
                              ],
                            ),
                          // If changeRoute is false, apply animation to "Ignore" button
                          if (!changeRoute)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // "Re-route" button
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
                                // Animated "Ignore" button
                                AnimatedBuilder(
                                  animation: _animationController,
                                  builder: (context, child) {
                                    return Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Animated Background on "Ignore"
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 120, maxHeight: 40), // Set a reasonable width
                                          child: Container(
                                            height: 50, // Match button height
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(50),
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.pinkAccent.withOpacity(0.5),
                                                  Colors.purple.withOpacity(0.9)
                                                ],
                                                stops: [
                                                  0.0,
                                                  _animationController.value
                                                ], // Progress effect from left to right
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // The actual "Ignore" button with text ABOVE the animation
                                        ElevatedButton(
                                          onPressed: () {
                                            isInteracted = true;
                                            _animationController.stop(); // Stop animation
                                            ignoreSwitchRoute?.call();
                                            overlayEntry.remove();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent, // Let animation show through
                                            shadowColor: Colors.transparent, // Remove unwanted shadow
                                          ),
                                          child: const Text(
                                            "Ignore",
                                            style: TextStyle(
                                                fontSize: 18.0, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      final overlay = Overlay.of(scaffoldMessengerKey.currentContext!);

      if (overlay != null) {
        overlay.insert(overlayEntry);

        Future.delayed(const Duration(seconds: 5), () {
          overlayEntry.remove();    
          if (!isInteracted) {
            // Perform action based on changeRoute flag
            if (changeRoute && onSwitchRoute != null) {
              // print("Pediu para switchRoute");
              onSwitchRoute!();
            } else if (!changeRoute && ignoreSwitchRoute != null) {
              // print("Pediu para ignorar switchRoute");
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

