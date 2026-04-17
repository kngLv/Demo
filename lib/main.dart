import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('app_demo/screen_time');

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'iOS App Restriction Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ScreenTimeDemoPage(),
    );
  }
}

class ScreenTimeDemoPage extends StatefulWidget {
  const ScreenTimeDemoPage({super.key});

  @override
  State<ScreenTimeDemoPage> createState() => _ScreenTimeDemoPageState();
}

class _ScreenTimeDemoPageState extends State<ScreenTimeDemoPage> {
  String _status = 'Ready';

  Future<void> _run(String method) async {
    setState(() {
      _status = 'Running: $method';
    });
    try {
      final dynamic result = await _channel.invokeMethod(method);
      setState(() {
        _status = '$method success: ${result ?? "ok"}';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = '$method failed: ${e.code} ${e.message ?? ""}';
      });
    } catch (e) {
      setState(() {
        _status = '$method failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('iOS App Restriction Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => _run('requestAuthorization'),
              child: const Text('1) Request Screen Time Access'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('pickApplications'),
              child: const Text('2) Pick Apps'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('applyRestriction'),
              child: const Text('3) Apply Restriction'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _run('clearRestriction'),
              child: const Text('4) Clear Restriction'),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tip: Requires a real iPhone and Family Controls entitlement.',
            ),
          ],
        ),
      ),
    );
  }
}
