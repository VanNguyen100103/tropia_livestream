import 'dart:convert';
import 'dart:io';
import 'dart:ui'; // Cần cho Color
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

// 1. IMPORT CÁC UTILS VÀ CONSTANTS
import 'package:tropia_mobile_app_android/core/constants/api_constants.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart'; // Mới thêm
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart'; // Để lấy index tab

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🌙 Handling a background message: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  String get baseUrl => ApiConstants.baseUrl; 
  
  FirebaseMessaging? _messaging;
  String? _fcmToken;
  int? _userId;

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  final AndroidNotificationChannel _channel = const AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
    playSound: true,
  );

  Future<void> initialize() async {
    _messaging = FirebaseMessaging.instance;
    await _setupLocalNotification();

    NotificationSettings settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ User granted permission');
      _fcmToken = await _messaging!.getToken();
      debugPrint('📲 FCM Token: $_fcmToken');

      await registerDevice();

      _messaging!.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('♻️ FCM Token refreshed: $newToken');
        registerDevice();
      });

      _setupMessageHandlers();
    } else {
      debugPrint('❌ User declined permission');
    }
  }

  Future<void> _setupLocalNotification() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotifications.initialize(
      settings: initializationSettings, 
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          debugPrint('🔔 Tapped local notification: ${response.payload}');
          try {
             _handleNotificationTap(jsonDecode(response.payload!));
          } catch (e) {
            debugPrint("Error parsing payload: $e");
          }
        }
      },
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Foreground Message received: ${message.notification?.title}');
      if (message.notification != null) {
        _showLocalNotification(message);
      }
      _handleNotificationData(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('👆 Notification Tapped (Background)');
      _handleNotificationTap(message.data);
    });

    _messaging!.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('🚀 Notification Tapped (Terminated)');
        _handleNotificationTap(message.data);
      }
    });
  }

  Future<void> registerDevice({int? userId}) async {
    if (_fcmToken == null) return;

    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceId = '';
      String osVersion = '';
      String deviceType = Platform.isAndroid ? 'android' : 'ios';

      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        osVersion = androidInfo.version.release;
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? '';
        osVersion = iosInfo.systemVersion;
      }

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String appVersion = packageInfo.version;

      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (userId != null) {
        _userId = userId;
        await prefs.setInt('user_id', userId);
      } else {
        _userId = prefs.getInt('user_id');
      }

      Map<String, dynamic> body = {
        'device_token': _fcmToken,
        'device_type': deviceType,
        'device_id': deviceId,
        'app_version': appVersion,
        'os_version': osVersion,
        'user_id': _userId 
      };

      final url = Uri.parse('${baseUrl}device-register');
      debugPrint('☁️ Calling API: $url');
      debugPrint('☁️ Body: $body');

      final appToken = prefs.getString('app_auth_token');
      if (appToken == null || appToken.isEmpty) {
        debugPrint('⚠️ Skip device-register: thiếu app_auth_token');
        return;
      }
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $appToken',
      };

      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['Result'] == true) {
          debugPrint('✅ Device registered successfully');
        } else {
          debugPrint('⚠️ Server returned false: ${data['StatusMess']}');
        }
      } else {
        debugPrint('⚠️ API Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Register Device Error: $e');
    }
  }

  void _showLocalNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: '@mipmap/ic_launcher',
            color: const Color(0xFFDA291C),
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  // --- 2. LOGIC XỬ LÝ BẤM VÀO THÔNG BÁO (ĐÃ CẬP NHẬT) ---
  void _handleNotificationTap(Map<String, dynamic> data) {
    String? deepLink = data['deep_link'];
    String? notificationId = data['notification_id'];
    
    // Đánh dấu đã đọc
    if (notificationId != null) {
      markAsRead(int.tryParse(notificationId) ?? 0);
    }

    if (deepLink != null) {
      debugPrint('🔗 Deep Link: $deepLink');

      // Logic chuyển Tab thông minh dùng Controller
      if (deepLink.contains("home")) {
        DashboardController.switchTab(DashboardPage.tabHome);
      } 
      else if (deepLink.contains("promotion")) {
        DashboardController.switchTab(DashboardPage.tabPromotions);
      }
      else if (deepLink.contains("ufresh")) {
        DashboardController.switchTab(DashboardPage.tabUfresh);
      }
      else if (deepLink.contains("cart")) {
        DashboardController.switchTab(DashboardPage.tabCart);
      }
      else if (deepLink.contains("profile")) {
        DashboardController.switchTab(DashboardPage.tabProfile);
      }
      else {
        // Nếu là các link khác (ví dụ chi tiết sản phẩm), 
        // bạn có thể dùng AppNavigator.push(...) ở đây
        debugPrint("⚠️ Deep link này chưa được xử lý: $deepLink");
      }
    }
  }

  void _handleNotificationData(Map<String, dynamic> data) {
  }

  Future<void> updateUserId(int userId) async {
    await registerDevice(userId: userId);
  }

  Future<void> clearUserId() async {
    _userId = null;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await registerDevice(); 
  }

Future<void> markAsRead(int notificationId) async {
     // 1. Đảm bảo có user_id (Lấy từ RAM hoặc Bộ nhớ máy)
     int? idToSend = _userId;
     if (idToSend == null) {
       SharedPreferences prefs = await SharedPreferences.getInstance();
       idToSend = prefs.getInt('user_id');
     }

     // Nếu vẫn không có user_id thì thôi, không gọi API
     if (idToSend == null) return;

     try {
       debugPrint('☁️ Marking read: Noti $notificationId - User $idToSend');
       
       // 2. Gọi API chuẩn theo format bạn gửi
       await http.post(
        Uri.parse('${baseUrl}notification-mark-read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'notification_id': notificationId,
          'user_id': idToSend, // Dùng biến vừa check
        }),
      );
     } catch (e) {
       debugPrint('❌ Error marking read: $e');
     }
  }
}
