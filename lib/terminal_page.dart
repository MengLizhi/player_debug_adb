import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

class TerminalPage extends StatefulWidget {
  final String deviceId;
  final String adbPath;

  const TerminalPage({super.key, required this.deviceId, required this.adbPath});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  late final terminal = Terminal(
    maxLines: 10000,
  );
  late final terminalController = TerminalController();
  Process? _shellProcess;
  final _utf8Decoder = const Utf8Decoder();

  @override
  void initState() {
    super.initState();
    _startShell();
  }

  Future<void> _startShell() async {
    try {
      _shellProcess = await Process.start(
        widget.adbPath,
        ['-s', widget.deviceId, 'shell'],
        mode: ProcessStartMode.normal,
      );

      // 处理终端输出
      _shellProcess!.stdout.listen(
        (List<int> data) {
          final text = _utf8Decoder.convert(data);
          terminal.write(text);
        },
        onDone: () {
          if (mounted) {
            Navigator.of(context).pop(); // 进程结束时关闭页面
          }
        },
      );

      _shellProcess!.stderr.listen(
        (List<int> data) {
          final text = _utf8Decoder.convert(data);
          terminal.write(text);
        },
      );

      // 设置终端输入回调
      terminal.onOutput = (String data) {
        _shellProcess?.stdin.write('$data\n');
        _shellProcess?.stdin.flush();
      };

      // 设置终端大小变化回调
      terminal.onResize = (w, h, pw, ph) {
        // Android shell 不支持终端大小调整，所以这里不需要处理
      };

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动终端失败: $e')),
        );
        Navigator.of(context).pop(); // 启动失败时关闭页面
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.deviceId),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: TerminalView(
          terminal,
          controller: terminalController,
        ),
      ),
    );
  }

  @override
  void dispose() {
    terminalController.dispose();
    // terminal.dispose(); // Removed as Terminal class does not have a dispose method
    _shellProcess?.kill(); // Correctly kill the shell process
    super.dispose();
  }
}