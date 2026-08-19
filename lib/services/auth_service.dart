import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final supabase = Supabase.instance.client;

  static bool get isAnonymous => supabase.auth.currentUser?.isAnonymous ?? true;
  static String? get currentEmail => supabase.auth.currentUser?.email;

  /// বর্তমান anonymous account-কে email/password দিয়ে upgrade করে — একই user_id, একই data থেকে যায়
  static Future<String?> linkEmail(String email, String password) async {
    try {
      await supabase.auth.updateUser(
        UserAttributes(email: email, password: password),
      );
      return null; // success
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong. Try again.';
    }
  }

  /// অন্য device-এ বা logout-এর পর existing account দিয়ে login
  static Future<String?> login(String email, String password) async {
    try {
      await supabase.auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Login failed. Check your email and password.';
    }
  }

  static Future<void> logout() async {
    await supabase.auth.signOut();
  }
}