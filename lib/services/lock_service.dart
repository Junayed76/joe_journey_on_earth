import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockService {
  static final _auth = LocalAuthentication();
  static const _prefKey = 'app_lock_enabled';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  static Future<bool> deviceSupportsLock() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'তোমার journal দেখার জন্য নিজেকে verify করো',
        options: const AuthenticationOptions(
          biometricOnly: false, // device PIN/pattern দিয়েও fallback করতে দেয়
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}