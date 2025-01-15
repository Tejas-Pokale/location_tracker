import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_platform_alert/flutter_platform_alert.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:geolocator/geolocator.dart';

@pragma(
    'vm:entry-point') // Mandatory if the App is obfuscated or using Flutter 3.1+
Future<void> callbackDispatcher() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  Workmanager().executeTask((task, inputData) async {
    try {
      Position position = await getCurrentLocation();
      await FirebaseFirestore.instance
          .collection('Locations')
          .doc('Tejas')
          .set({
        'location': FieldValue.arrayUnion([
          {
            'location': {
              'lat': position.latitude.toString(),
              'long': position.longitude.toString(),
            },
            'timestamp': '${DateTime.now()} from workmanager',
          }
        ]),
      }, SetOptions(merge: true)).then(
        (value) {
          showNotification({
            'title': 'Location updated from work manager',
            'body': 'Lat : ${position.latitude} | long : ${position.longitude}'
          });
        },
      );

      bool isRunning = await FlutterBackgroundService().isRunning();
      if (!isRunning) {
        await initializeService();
      }
    } catch (err) {
      Logger().e(err
          .toString()); // Logger flutter package, prints error on the debug console
      throw Exception(err);
    }

    return Future.value(true);
  });
}

// Be sure to annotate your callback function to avoid issues in release mode on Flutter >= 3.3.0
@pragma('vm:entry-point')
Future<void> printHello() async {
  final DateTime now = DateTime.now();
  final int isolateId = Isolate.current.hashCode;
  print("[$now] Hello, world! isolate=${isolateId} function='$printHello'");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  updateLocation();

  bool isRunning = await FlutterBackgroundService().isRunning();
  if (!isRunning) {
    await initializeService();
  }
}

Future<void> updateLocation() async {
  Position position = await getCurrentLocation();

  FirebaseFirestore.instance.collection('Locations').doc('Tejas').set({
    'location': FieldValue.arrayUnion([
      {
        'location': {
          'lat': position.latitude.toString(),
          'long': position.longitude.toString(),
        },
        'timestamp': '${DateTime.now()} from alram manager',
      }
    ]),
  }, SetOptions(merge: true)).then(
    (value) {
      showNotification({
        'title': 'Location updated from alarm manager',
        'body': 'Lat : ${position.latitude} | long : ${position.longitude}'
      });
    },
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await DisableBatteryOptimization.showEnableAutoStartSettings(
      "Enable Auto Start",
      "Follow the steps and enable the auto start of this app");
  await DisableBatteryOptimization.showDisableBatteryOptimizationSettings();
  await DisableBatteryOptimization
      .showDisableManufacturerBatteryOptimizationSettings(
          "Your device has additional battery optimization",
          "Follow the steps and disable the optimizations to allow smooth functioning of this app");

  await getPermissions();

  AwesomeNotifications().initialize(
    'resource://drawable/launch_background',
    [
      NotificationChannel(
        channelKey: 'basic_channel',
        channelName: 'Basic notifications',
        channelDescription: 'Notification from alaram manager',
        defaultColor: Color(0xFF9D50DD),
        ledColor: Colors.white,
        criticalAlerts: false,
        importance: NotificationImportance.High,
        playSound: true,
        locked: true,
      ),
    ],
  );

  Workmanager().initialize(
    callbackDispatcher, // The top level function, aka callbackDispatcher
    isInDebugMode: true,
  );
  Workmanager().registerPeriodicTask(
    "periodic-task-identifier",
    "simplePeriodicTask",
    // When no frequency is provided the default 15 minutes is set.
    // Minimum frequency is 15 min. Android will automatically change your frequency to 15 min if you have configured a lower frequency.
    frequency: Duration(minutes: 15),
  );
  await initializeService();
  await AndroidAlarmManager.initialize();
  runApp(const MyApp());

  final int helloAlarmID = 0;
  await AndroidAlarmManager.periodic(
      const Duration(seconds: 10), helloAlarmID, printHello);
}

Future getPermissions() async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }
}

Future<Position> getCurrentLocation() async {
  const LocationSettings locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 100,
  );

  return await Geolocator.getCurrentPosition(
      locationSettings: locationSettings);
}

// this will be used as notification channel id
const notificationChannelId = 'my_foreground';

// this will be used for notification id, So you can update your custom notification with this id.
const notificationId = 888;

Future<void> initializeService() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notificationChannelId, // id
    'MY FOREGROUND SERVICE', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.low, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
      androidConfiguration: AndroidConfiguration(
        // this will be executed when app is in foreground or background in separated isolate
        onStart: onStart,
        // auto start service
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId:
            notificationChannelId, // this must match with notification channel you created above.
        initialNotificationTitle: 'AWESOME SERVICE',
        initialNotificationContent: 'Location fetching in background',
        foregroundServiceNotificationId: notificationId,
        autoStartOnBoot: true,
      ),
      iosConfiguration: IosConfiguration());
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // bring to foreground
  // Timer.periodic(const Duration(seconds: 1), (timer) async {
  //   await FlutterPlatformAlert.playAlertSound();
  //   if (service is AndroidServiceInstance) {
  //     if (await service.isForegroundService()) {
  //       flutterLocalNotificationsPlugin.show(
  //         notificationId,
  //         'COOL SERVICE',
  //         'Awesome ${DateTime.now()}',
  //         const NotificationDetails(
  //           android: AndroidNotificationDetails(
  //             notificationChannelId,
  //             'MY FOREGROUND SERVICE',
  //             icon: 'ic_bg_service_small',
  //             ongoing: true,
  //           ),
  //         ),
  //       );
  //     }
  //   }
  // });

  late LocationSettings locationSettings;

  if (defaultTargetPlatform == TargetPlatform.android) {
    locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5),
        //(Optional) Set foreground notification config to keep the app alive
        //when going to the background
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText:
              "Example app will continue to receive your location even when you aren't using it",
          notificationTitle: "Running in Background",
          enableWakeLock: true,
        ));
  } else if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    locationSettings = AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.fitness,
      distanceFilter: 1,
      pauseLocationUpdatesAutomatically: true,
      // Only set to true if our app will be started up in the background.
      showBackgroundLocationIndicator: false,
    );
  } else if (kIsWeb) {
    locationSettings = WebSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
      maximumAge: Duration(minutes: 5),
    );
  } else {
    locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );
  }

// supply location settings to getPositionStream
  StreamSubscription<Position> positionStream =
      Geolocator.getPositionStream(locationSettings: locationSettings)
          .listen((Position? position) async {
    print(position == null
        ? 'Unknown'
        : '${position.latitude.toString()}, ${position.longitude.toString()}');
    await FlutterPlatformAlert.playAlertSound();
    showNotification({
      'title': 'From Background service',
      'body':
          'lat : ${position!.latitude.toString()} | long : ${position.longitude.toString()}'
    });
  });
}

void showNotification(Map<String, dynamic> data) {
  AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: 10,
      channelKey: 'basic_channel',
      title: data['title'],
      body: data['body'],
      notificationLayout: NotificationLayout.BigPicture,
      criticalAlert: false,
    ),
    actionButtons: [
      NotificationActionButton(
        key: 'accept',
        label: 'Accept',
        color: Colors.green,
      ),
      NotificationActionButton(
        key: 'reject',
        label: 'Reject',
        color: Colors.red,
      ),
    ],
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
