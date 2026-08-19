import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>?> getMyProfile() async {
    final userId = supabase.auth.currentUser!.id;
    return await supabase.from('profiles').select().eq('id', userId).maybeSingle();
  }

  static Future<void> updateUsername(String username) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.from('profiles').upsert({'id': userId, 'username': username, 'updated_at': DateTime.now().toIso8601String()});
  }

  static Future<String?> uploadAvatar(File file) async {
    final userId = supabase.auth.currentUser!.id;
    final ext = file.path.split('.').last;
    final path = '$userId/avatar.$ext';

    await supabase.storage.from('avatars').upload(path, file, fileOptions: const FileOptions(upsert: true));
    final url = supabase.storage.from('avatars').getPublicUrl(path);

    await supabase.from('profiles').upsert({'id': userId, 'avatar_url': url, 'updated_at': DateTime.now().toIso8601String()});
    return url;
  }
}