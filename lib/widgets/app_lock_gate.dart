import 'package:flutter/material.dart';
import '../services/lock_service.dart';
import '../theme/app_theme.dart';
import 'app_loading_screen.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = true;
  bool _lockEnabled = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _lockEnabled) {
      setState(() => _locked = true); // background-এ গেলে আবার lock হয়ে যাবে
    }
  }

  Future<void> _checkLock() async {
    final enabled = await LockService.isEnabled();
    if (!mounted) return;
    setState(() {
      _lockEnabled = enabled;
      _locked = enabled;
      _checking = false;
    });
    if (enabled) _tryUnlock();
  }

  Future<void> _tryUnlock() async {
    final success = await LockService.authenticate();
    if (!mounted) return;
    if (success) {
      setState(() => _locked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const AppLoadingScreen();
    }

    if (_lockEnabled && _locked) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 56, color: AppColors.terracotta),
              const SizedBox(height: 16),
              Text(
                'App locked',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock'),
                onPressed: _tryUnlock,
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}