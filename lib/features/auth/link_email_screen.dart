import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class LinkEmailScreen extends StatefulWidget {
  const LinkEmailScreen({super.key});
  @override
  State<LinkEmailScreen> createState() => _LinkEmailScreenState();
}

class _LinkEmailScreenState extends State<LinkEmailScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'Valid email আর কমপক্ষে ৬ characters-এর password দাও।');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final err = await AuthService.linkEmail(email, password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account saved! এখন এই email দিয়ে login করা যাবে।')),
      );
      Navigator.pop(context);
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Save your account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Email আর password যোগ করো, যাতে অন্য device-এও তোমার journal access করতে পারো আর data হারিয়ে না যায়।',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}