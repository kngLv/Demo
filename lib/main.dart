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
  Future<void> _run(String method, {Map<String, dynamic>? arguments}) async {
    setState(() {
      _status = '执行中：$method';
    });
    try {
      final dynamic result = await _channel.invokeMethod(method, arguments);
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
              child: const Text('1) 申请权限'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('pickApplications'),
              child: const Text('2) 选择应用'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('openRestrictionCenter'),
              child: const Text('3) 应用限制与定时'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('openNativeUsageDashboard'),
              child: const Text('4) 方案1-原生定制页'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FlutterBridgeReportPage(),
                  ),
                );
              },
              child: const Text('5) 方案2-Flutter桥接页'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _run('showUsageReport'),
              child: const Text('6) 方案3-系统报告页'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _run('clearRestriction'),
              child: const Text('7) 解除限制'),
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

class FlutterBridgeReportPage extends StatefulWidget {
  const FlutterBridgeReportPage({super.key});

  @override
  State<FlutterBridgeReportPage> createState() => _FlutterBridgeReportPageState();
}

class _FlutterBridgeReportPageState extends State<FlutterBridgeReportPage> {
  int _daysAgo = 0;
  String _selectionStatus = '尚未更新选择';

  String _labelFor(int daysAgo) {
    if (daysAgo == 0) return '今天';
    if (daysAgo == 1) return '昨天';
    return '$daysAgo 天前';
  }

  Future<void> _pickApps() async {
    try {
      final dynamic result = await _channel.invokeMethod('pickApplications');
      setState(() {
        _selectionStatus = '${result ?? '完成选择'}';
      });
    } on PlatformException catch (e) {
      setState(() {
        _selectionStatus = '选择失败：${e.code} ${e.message ?? ""}';
      });
    }
  }

  Future<void> _showReport() async {
    await _channel.invokeMethod(
      'showUsageReportForDay',
      <String, dynamic>{'daysAgo': _daysAgo},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('方案2 - Flutter桥接页')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('已选应用：$_selectionStatus'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _pickApps,
              child: const Text('添加 App'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _daysAgo,
              decoration: const InputDecoration(
                labelText: '统计日期',
                border: OutlineInputBorder(),
              ),
              items: List.generate(
                7,
                (i) => DropdownMenuItem<int>(
                  value: i,
                  child: Text(_labelFor(i)),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _daysAgo = value ?? 0;
                });
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _showReport,
              child: const Text('查看使用时长'),
            ),
          ],
        ),
      ),
    );
  }
}

enum TimedMode { countdown, dailyWindow }

class TimedHideConfigPage extends StatefulWidget {
  const TimedHideConfigPage({super.key});

  @override
  State<TimedHideConfigPage> createState() => _TimedHideConfigPageState();
}

class _TimedHideConfigPageState extends State<TimedHideConfigPage> {
  TimedMode _mode = TimedMode.countdown;
  int _minutes = 60;
  TimeOfDay _start = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 7, minute: 0);
  String _status = '未配置';
  String _currentSchedule = '未读取';

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  int _toMinuteOfDay(TimeOfDay t) => t.hour * 60 + t.minute;
  String _hhmmFromMinute(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  Future<void> _pickTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  Future<void> _apply() async {
    try {
      if (_mode == TimedMode.countdown) {
        final dynamic res = await _channel.invokeMethod(
          'configureTimedRestriction',
          <String, dynamic>{
            'mode': 'countdown',
            'minutes': _minutes,
          },
        );
        setState(() {
          _status = '${res ?? "已开启"}';
        });
        await _refreshStatus();
        return;
      }

      final dynamic res = await _channel.invokeMethod(
        'configureTimedRestriction',
        <String, dynamic>{
          'mode': 'dailyWindow',
          'startMinute': _toMinuteOfDay(_start),
          'endMinute': _toMinuteOfDay(_end),
        },
      );
      setState(() {
        _status = '${res ?? "已开启"}';
      });
      await _refreshStatus();
    } on PlatformException catch (e) {
      setState(() {
        _status = '失败：${e.code} ${e.message ?? ""}';
      });
    }
  }

  Future<void> _cancel() async {
    try {
      final dynamic res = await _channel.invokeMethod('cancelTimedRestriction');
      setState(() {
        _status = '${res ?? "已取消"}';
      });
      await _refreshStatus();
    } on PlatformException catch (e) {
      setState(() {
        _status = '失败：${e.code} ${e.message ?? ""}';
      });
    }
  }

  Future<void> _refreshStatus() async {
    try {
      final dynamic data = await _channel.invokeMethod('getTimedRestrictionStatus');
      final map = (data is Map) ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      final enabled = map['enabled'] == true;
      if (!enabled) {
        setState(() {
          _currentSchedule = '当前未开启系统定时隐藏';
        });
        return;
      }
      final mode = (map['mode'] ?? '').toString();
      if (mode == 'countdown') {
        final minutes = map['minutes'] ?? '-';
        setState(() {
          _currentSchedule = '当前计划：倒计时 $minutes 分钟';
        });
        return;
      }
      if (mode == 'dailyWindow') {
        final startMinute = map['startMinute'] as int? ?? 0;
        final endMinute = map['endMinute'] as int? ?? 0;
        setState(() {
          _currentSchedule =
              '当前计划：每日 ${_hhmmFromMinute(startMinute)} - ${_hhmmFromMinute(endMinute)}';
        });
        return;
      }
      setState(() {
        _currentSchedule = '当前计划：未知模式 $mode';
      });
    } on PlatformException catch (e) {
      setState(() {
        _currentSchedule = '读取失败：${e.code} ${e.message ?? ""}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('定时隐藏配置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<TimedMode>(
              segments: const [
                ButtonSegment<TimedMode>(
                  value: TimedMode.countdown,
                  label: Text('倒计时'),
                ),
                ButtonSegment<TimedMode>(
                  value: TimedMode.dailyWindow,
                  label: Text('每日时段'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) {
                setState(() {
                  _mode = value.first;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              _currentSchedule,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _refreshStatus,
              child: const Text('刷新系统调度状态'),
            ),
            const SizedBox(height: 16),
            if (_mode == TimedMode.countdown) ...[
              Text('隐藏时长：$_minutes 分钟'),
              Slider(
                value: _minutes.toDouble(),
                min: 10,
                max: 480,
                divisions: 47,
                label: '$_minutes 分钟',
                onChanged: (value) {
                  setState(() {
                    _minutes = value.round();
                  });
                },
              ),
            ] else ...[
              OutlinedButton(
                onPressed: () => _pickTime(
                  initial: _start,
                  onPicked: (v) => setState(() => _start = v),
                ),
                child: Text('开始时间：${_start.format(context)}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _pickTime(
                  initial: _end,
                  onPicked: (v) => setState(() => _end = v),
                ),
                child: Text('结束时间：${_end.format(context)}'),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _apply,
              child: const Text('开启定时隐藏'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _cancel,
              child: const Text('取消定时隐藏'),
            ),
            const SizedBox(height: 16),
            Text('状态：$_status'),
          ],
        ),
      ),
    );
  }
}
