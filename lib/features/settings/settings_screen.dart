import 'package:flutter/material.dart';
import 'package:joe_journey_on_earth/features/settings/profile_edit_screen.dart';
import '../../services/auth_service.dart';
import '../../services/lock_service.dart';
import '../../theme/app_theme.dart';
import '../auth/link_email_screen.dart';
import '../auth/login_screen.dart';
import '../../services/profile_service.dart';
import '../story/story_feed_screen.dart';
import 'profile_edit_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {


  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadLockState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final data = await ProfileService.getMyProfile();
    if (mounted) setState(() => _profile = data);
  }

  bool _lockEnabled = false;
  bool _lockSupported = true;



  Future<void> _loadLockState() async {
    final enabled = await LockService.isEnabled();
    final supported = await LockService.deviceSupportsLock();
    if (mounted) {
      setState(() {
        _lockEnabled = enabled;
        _lockSupported = supported;
      });
    }
  }

  Future<void> _toggleLock(bool value) async {
    if (value) {
      final ok = await LockService.authenticate();
      if (!ok) return; // verify না হলে enable করবে না
    }
    await LockService.setEnabled(value);
    if (mounted) setState(() => _lockEnabled = value);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('তুমি নিশ্চিত? Log out করলে আবার login করতে হবে data দেখতে।'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService.logout();
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAnon = AuthService.isAnonymous;
    final email = AuthService.currentEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [

          InkWell(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen()));
              _loadProfile(); // ফিরে এসে নতুন তথ্য refresh করো
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.terracottaSoft,
                    backgroundImage: _profile?['avatar_url'] != null ? NetworkImage(_profile!['avatar_url']) : null,
                    child: _profile?['avatar_url'] == null
                        ? Icon(Icons.person, size: 30, color: AppColors.terracotta)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_profile?['username'] as String?)?.isNotEmpty == true
                              ? _profile!['username']
                              : 'নাম যোগ করো',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark),
                        ),
                        const SizedBox(height: 2),
                        Text('Profile edit করতে tap করো', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          const Divider(height: 28),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Community', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ListTile(
            leading: Icon(Icons.public, color: AppColors.terracotta),
            title: const Text('Community stories'),
            subtitle: const Text('Optional — তোমার journal অন্যদের সাথে share করো, চাইলে'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StoryFeedScreen())),
          ),
          const Divider(height: 32),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          SwitchListTile(
            secondary: Icon(Icons.dark_mode_outlined, color: AppColors.terracotta),
            title: const Text('Dark mode'),
            subtitle: const Text('Light আর dark-এর মধ্যে বদলাও'),
            value: AppColors.isDark,
            onChanged: (value) async {
              await AppTheme.toggleDarkMode(value);
              setState(() {});
            },
          ),
          const Divider(height: 32),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Account', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          if (isAnon)
            ListTile(
              leading: const Icon(Icons.cloud_off, color: Colors.orange),
              title: const Text('Account not saved'),
              subtitle: const Text('Data harabe app uninstall korle. Save korte tap koro.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LinkEmailScreen())),
            )
          else ...[
            ListTile(
              leading: Icon(Icons.person_outline, color: AppColors.terracotta),
              title: const Text('Edit profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.email, color: Colors.green),
              title: Text(email ?? ''),
              subtitle: const Text('Logged in'),
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Log in with a different account'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log out'),
            onTap: _logout,
          ),



          const Divider(height: 32),
          // পরের feature গুলো (App lock, Profile ইত্যাদি) এখানে যোগ হবে

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Security', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint, color: Colors.deepPurple),
            title: const Text('App lock'),
            subtitle: Text(_lockSupported
                ? 'Fingerprint / PIN দিয়ে journal protect করো'
                : 'এই device-এ lock support নেই'),
            value: _lockEnabled,
            onChanged: _lockSupported ? _toggleLock : null,
          ),
          const Divider(height: 32),

        ],
      ),
    );
  }
}