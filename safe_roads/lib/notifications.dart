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
      print("Foreground message received: ${message.data['title']}");
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

    flutterLocalNotificationsPlugin.show(
      0,
      null, // message.data['title'] 
      null, // message.data['body'] 
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
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        String languageCode = Provider.of<UserPreferences>(context, listen: false).languageCode;

        print("Estou a entrar no OverLay");

        return StatefulBuilder(
          builder: (context, setState) {
            animationController = AnimationController(
              vsync: Navigator.of(context),
              duration: const Duration(seconds: 6),
            );

            animationController.forward();

            return Positioned(
              top: showButton ? screenHeight * 0.1 : screenHeight * 0.65,
              left: screenWidth * 0.01,
              right: screenWidth * 0.01,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: EdgeInsets.all(screenWidth * 0.04),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(screenWidth * 0.03),
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
                        message.data['title'] ?? 'Notification',
                        style: TextStyle(
                          fontSize: screenWidth * 0.05,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Text(
                        message.data['body']  ?? '',
                        style: TextStyle(fontSize: screenWidth * 0.04),
                        textAlign: TextAlign.center,
                      ),
                      if (showButton) ...[
                        if (changeRoute)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              AnimatedBuilder(
                                animation: animationController,
                                builder: (context, child) {
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: screenWidth * 0.4,
                                          maxHeight: screenHeight * 0.06,
                                        ),
                                        child: Container(
                                          height: screenHeight * 0.06,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(50),
                                            gradient: LinearGradient(
                                              colors: [
                                                const Color.fromARGB(255, 62, 62, 62).withOpacity(0.5),
                                                Colors.black.withOpacity(0.9)
                                              ],
                                              stops: [0.0, animationController.value],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          isInteracted = true;
                                          animationController.stop();
                                          onSwitchRoute?.call();
                                          overlayEntry.remove();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                        ),
                                        child: Text(
                                          LanguageConfig.getLocalizedString(languageCode, 'reRouteButton'),
                                          style: TextStyle(
                                            fontSize: screenWidth * 0.045,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  isInteracted = true;
                                  animationController.stop();
                                  ignoreSwitchRoute?.call();
                                  overlayEntry.remove();
                                },
                                child: Text(
                                  LanguageConfig.getLocalizedString(languageCode, 'ignoreButton'),
                                  style: TextStyle(fontSize: screenWidth * 0.045),
                                ),
                              ),
                            ],
                          ),
                        if (!changeRoute)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  isInteracted = true;
                                  onSwitchRoute?.call();
                                  overlayEntry.remove();
                                },
                                child: Text(
                                  LanguageConfig.getLocalizedString(languageCode, 'reRouteButton'),
                                  style: TextStyle(fontSize: screenWidth * 0.045),
                                ),
                              ),
                              AnimatedBuilder(
                                animation: animationController,
                                builder: (context, child) {
                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: screenWidth * 0.4,
                                          maxHeight: screenHeight * 0.06,
                                        ),
                                        child: Container(
                                          height: screenHeight * 0.06,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(50),
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.pinkAccent.withOpacity(0.5),
                                                Colors.purple.withOpacity(0.9)
                                              ],
                                              stops: [0.0, animationController.value],
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                            ),
                                          ),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          isInteracted = true;
                                          animationController.stop();
                                          ignoreSwitchRoute?.call();
                                          overlayEntry.remove();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                        ),
                                        child: Text(
                                          LanguageConfig.getLocalizedString(languageCode, 'ignoreButton'),
                                          style: TextStyle(
                                            fontSize: screenWidth * 0.045,
                                            color: Colors.white,
                                          ),
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

