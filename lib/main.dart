import 'package:flutter/material.dart';
import 'package:joe_journey_on_earth/theme/app_theme.dart';
import 'package:joe_journey_on_earth/widgets/app_lock_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/main/main_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'storedUrl',
    publishableKey: 'storedPublishableKey',
  );
  // Creates Anonymous User
  if (Supabase.instance.client.auth.currentUser == null) {
    await Supabase.instance.client.auth.signInAnonymously();
  }
  try {
    await NotificationService.init();
    await NotificationService.scheduleDailyNotification(hour: 20, minute: 0);
  } catch (e) {
    debugPrint('Notification setup failed: $e');
  }
  await AppTheme.loadSavedTheme();
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppTheme.rebuildNotifier,
      builder: (context, tick, __) {
        return MaterialApp(
          key: ValueKey(tick), // থিম বদলালে পুরো widget tree fresh build হবে
          title: 'Journey On Earth',
          theme: AppTheme.theme,
          home: AppLockGate(child: MainScreen()),
        );
      },
    );
  }
}