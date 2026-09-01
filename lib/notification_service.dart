import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:cloud_firestore/cloud_firestore.dart';



class BildirimServisi {

  static final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();



  static Future<void> init() async {

    const AndroidInitializationSettings androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(android: androidInitSettings);

    await _localNotificationsPlugin.initialize(initSettings);



    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();



    if (settings.authorizationStatus == AuthorizationStatus.authorized) {

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {

        if (message.notification != null) {

          _bildirimGoster(message.notification!.title, message.notification!.body);

        }

      });

    }

  }



  static Future<void> _bildirimGoster(String? title, String? body) async {

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(

      'araba_yikama_kanal',

      'Araba Yıkama Bildirimleri',

      importance: Importance.max,

      priority: Priority.high,

    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _localNotificationsPlugin.show(0, title, body, platformDetails);

  }



  static Future<void> tokenKaydet(String uid) async {

    String? token = await FirebaseMessaging.instance.getToken();

    if (token != null) {

      await FirebaseFirestore.instance.collection('kullanicilar').doc(uid).update({

        'fcmToken': token,

      });

    }

  }

} 

