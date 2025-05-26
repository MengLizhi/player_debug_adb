import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:player_debug_adb/logcat_page.dart';
import 'package:player_debug_adb/terminal_page.dart';
import 'package:process_run/shell.dart';
import 'package:file_picker/file_picker.dart';
import 'adb_manager.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ADB Device Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MyHomePage(title: 'ADB Device Manager'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final AdbManager _adbManager = AdbManager();
  List<String> _devices = [];
  bool _isLoading = false;
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '5555',
  );

  @override
  void initState() {
    super.initState();
    // 在应用启动时检查 ADB 路径
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_adbManager.isAdbPathSet) {
        showDialog(
          context: context,
          barrierDismissible: false, // 禁止点击外部关闭
          builder: (context) => AlertDialog(
            title: const Text('设置 ADB'),
            content: const Text('请选择 adb.exe 文件的位置'),
            actions: [
              TextButton(
                onPressed: () => _selectAdbPath(),
                child: const Text('选择'),
              ),
            ],
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _showConnectDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP地址',
                hintText: '例如: 192.168.1.100',
              ),
            ),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '默认: 5555',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _connectDevice(_ipController.text, _portController.text);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectDevice(String ip, String port) async {
    if (!_adbManager.isAdbPathSet) {
      await _selectAdbPath();
      return;
    }

    if (ip.isEmpty) {
      _showResultDialog(false, '请输入IP地址');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      var shell = Shell(
        runInShell: true,
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );
      // 执行连接命令并获取输出
      var result = await shell.run(
        '"${_adbManager.adbPath}" connect $ip:$port',
      );

      // 获取输出内容（优先使用stderr，因为错误信息通常在stderr中）
      String output = '';
      if (result.first.stderr.isNotEmpty) {
        output = result.first.stderr;
      } else {
        output = result.first.stdout;
      }

      // 清理输出内容
      output = output.trim();

      // 分析输出结果
      if (output.contains('connected') ||
          output.contains('already connected')) {
        _showResultDialog(true, '设备连接成功');
        // 连接成功后刷新设备列表
        await _getDevices();
      } else {
        _showResultDialog(false, '连接失败：$output');
      }
    } catch (e) {
      debugPrint('Error: $e');
      String errorMsg = e.toString();
      _showResultDialog(false, '连接错误：$errorMsg');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showResultDialog(bool success, String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(success ? '连接成功' : '连接失败'),
        content: Text(message),
        icon: Icon(
          success ? Icons.check_circle : Icons.error,
          color: success ? Colors.green : Colors.red,
          size: 48,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAdbPath() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['exe'],
      dialogTitle: '选择adb.exe文件',
    );

    if (result != null) {
      _adbManager.adbPath = result.files.single.path;
      // 关闭设置弹窗
      if (!mounted) return;
      Navigator.of(context).pop();
      _getDevices(); // 重新获取设备列表
    }
  }

  Future<void> _getDevices() async {
    if (!_adbManager.isAdbPathSet) {
      await _selectAdbPath();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      var shell = Shell();
      var result = await shell.run('"${_adbManager.adbPath}" devices');
      var output = result.first.stdout.toString();
      var lines = output.split('\n');

      var devices = lines
          .skip(1)
          .where((line) => line.trim().isNotEmpty)
          .map((line) => line.split('\t').first)
          .toList();

      setState(() {
        _devices = devices;
      });
    } catch (e) {
      debugPrint('Error: $e');
      // 如果执行出错，可能是ADB路径无效，提示用户重新选择
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('执行ADB命令失败，请重新选择ADB文件')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openTerminal(String deviceId) async {
    if (!_adbManager.isAdbPathSet) return;

    // 导航到终端页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TerminalPage(
          deviceId: deviceId,
          adbPath: _adbManager.adbPath ?? '',
        ),
      ),
    );
  }

  Future<void> _openShell(String deviceId) async {
    if (!_adbManager.isAdbPathSet) return;

    try {
      var shell = Shell(
        runInShell: true,
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );
      await shell.run('"${_adbManager.adbPath}" -s $deviceId shell');
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('打开终端失败')));
      }
    }
  }

  Future<void> _openLogcat(String deviceId) async {
    if (!_adbManager.isAdbPathSet) return;

    // 导航到日志页面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => LogcatPage(
          deviceId: deviceId,
          adbPath: _adbManager.adbPath ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showConnectDialog,
            tooltip: '添加设备',
          ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _selectAdbPath,
            tooltip: '选择ADB文件',
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : _devices.isEmpty
            ? const Text('没有找到已连接的设备')
            : ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final deviceId = _devices[index];
                  return ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(deviceId),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.terminal),
                          onPressed: () => _openTerminal(deviceId),
                          tooltip: '打开终端',
                        ),
                        IconButton(
                          icon: const Icon(Icons.article),
                          onPressed: () => _openLogcat(deviceId),
                          tooltip: '查看日志',
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getDevices,
        tooltip: '刷新设备列表',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
