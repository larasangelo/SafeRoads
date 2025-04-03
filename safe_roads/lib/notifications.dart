import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:safe_roads/configuration/language_config.dart';
import 'dart:async';

import 'package:safe_roads/models/user_preferences.dart';

class Notifications {
  static final Notifications _instance = Notifications._internal();
  factory Notifications() => _instance;
  Notifications._internal();  // Singleton pattern

  BuildContext? _latestContext;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();  // Defined once

  // final NavigationService _navigationService = NavigationService();

  // Set the context for notifications
  void setContext(BuildContext context) {
    _latestContext = context;
  }

  String? fcmToken;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  final AndroidInitializationSettings androidInitializationSettings = const AndroidInitializationSettings('@mipmap/ic_launcher');

  // Callback function for navigation
  VoidCallback? onSwitchRoute;
  VoidCallback? ignoreSwitchRoute;

  Future<StreamSubscription<RemoteMessage>?> setupFirebaseMessaging(BuildContext? context, StreamSubscription<RemoteMessage>? messageSubscription) async {
  NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    criticalAlert: true, // For iOS to allow critical notifications
    announcement: true,  // For accessibility-related announcements
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print("Notification permission granted");
    fcmToken = await FirebaseMessaging.instance.getToken();
    print("FCM Token: $fcmToken");

    if (messageSubscription != null) {
      messageSubscription.resume(); 
      return messageSubscription;
    }

    messageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Foreground message received: ${message.notification?.title}");
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showForegroundNotification(message);
      });
    });

    return messageSubscription;
  } else {
    print("Notification permission denied");
  }
  return null;
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

  final AudioPlayer _audioPlayer = AudioPlayer();

  void playNotificationSound() async {
    try {
      // Play the sound from the asset
      await _audioPlayer.play(AssetSource('notification.mp3'));
      print("Notification sound is playing.");
      _audioPlayer.onPlayerComplete.listen((event) {
        print("Notification sound has finished playing.");
      });
    } catch (e) {
      print("Error playing sound: $e");
    }
  }
  
  void showForegroundNotification(RemoteMessage message) async {
    if (_latestContext == null) {
      print("No valid context available to show notification.");
      return;
    }

    if (message.notification != null) {
      flutterLocalNotificationsPlugin.show(
        0,
        null, // message.notification!.title
        null, // message.notification!.body
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'channel_id_1', // Must match the channel ID
            'Default Notifications',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            icon: '@mipmap/ic_launcher',
            visibility: NotificationVisibility.secret, // Hidden notification
            showWhen: false, // Prevents the time from being shown
            shortcutId: "silent_notification", //unique Id
          ),
        ),
      );
      // playNotificationSound();

      bool showButton = message.data['button'] == 'true'; 
      bool changeRoute = message.data['changeRoute'] == 'true';

      final overlay = Overlay.of(_latestContext!, rootOverlay: true);

      late OverlayEntry overlayEntry;
      bool isInteracted = false; 

      // AnimationController for smooth progress transition
      late AnimationController animationController;

      overlayEntry = OverlayEntry(
        builder: (context) {
        String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;
          return StatefulBuilder(
            builder: (context, setState) {
              animationController = AnimationController(
                vsync: Navigator.of(context), // Ensures smooth animations
                duration: const Duration(seconds: 6), // Full duration
              );

              animationController.forward(); // Start animation immediately

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
                                  animation: animationController,
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
                                                  animationController.value
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
                                            animationController.stop(); // Stop animation
                                            onSwitchRoute?.call();
                                            overlayEntry.remove();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent, // Let animation show through
                                            shadowColor: Colors.transparent, // Remove unwanted shadow
                                          ),
                                          child: Text(
                                            LanguageConfig.getLocalizedString(languageCode, 'reRouteButton'),
                                            style: const TextStyle(
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
                                    animationController.stop(); // Stop animation
                                    ignoreSwitchRoute?.call();
                                    overlayEntry.remove();
                                  },
                                  child: Text( LanguageConfig.getLocalizedString(languageCode, 'ignoreButton'), style: const TextStyle(fontSize: 18.0)),
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
                                  child: Text(LanguageConfig.getLocalizedString(languageCode, 'reRouteButton'), style: const TextStyle(fontSize: 18.0)),
                                ),
                                // Animated "Ignore" button
                                AnimatedBuilder(
                                  animation: animationController,
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
                                                  animationController.value
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
                                            animationController.stop(); // Stop animation
                                            ignoreSwitchRoute?.call();
                                            overlayEntry.remove();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent, // Let animation show through
                                            shadowColor: Colors.transparent, // Remove unwanted shadow
                                          ),
                                          child: Text(
                                            LanguageConfig.getLocalizedString(languageCode, 'ignoreButton'),
                                            style: const TextStyle(
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

      overlay.insert(overlayEntry);

      Future.delayed(const Duration(seconds: 5), () {
        overlayEntry.remove();    
        if (!isInteracted) {
          // Perform action based on changeRoute flag
          if (changeRoute && onSwitchRoute != null) {
            onSwitchRoute!();
          } else if (!changeRoute && ignoreSwitchRoute != null) {
            ignoreSwitchRoute!();
          }
        }
      });
    }
  }
}

