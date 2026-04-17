import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Flutter 与 iOS 原生通信通道（Screen Time 能力在 iOS 原生侧实现）
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
  String _status = '准备就绪';

  // 通用调用器：按方法名触发 iOS 侧能力，并回显状态
  Future<void> _run(String method) async {
    setState(() {
      _status = '执行中：$method';
    });
    try {
      final dynamic result = await _channel.invokeMethod(method);
      setState(() {
        _status = '$method 成功：${result ?? "完成"}';
      });
    } on PlatformException catch (e) {
      setState(() {
        _status = '$method 失败：${e.code} ${e.message ?? ""}';
      });
    } catch (e) {
      setState(() {
        _status = '$method 失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('iOS 应用访问限制 Demo')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: () => _run('requestAuthorization'),
              child: const Text('1) 申请屏幕使用时间权限'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('pickApplications'),
              child: const Text('2) 选择应用'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('applyRestriction'),
              child: const Text('3) 应用限制'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _run('clearRestriction'),
              child: const Text('4) 解除限制'),
            ),
            const SizedBox(height: 24),
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              '提示：需要真机 iPhone 和 Family Controls 能力开通。',
            ),
          ],
        ),
      ),
    );
  }
}
