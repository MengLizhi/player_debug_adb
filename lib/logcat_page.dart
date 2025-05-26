import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:process_run/shell.dart';
import 'package:data_table_2/data_table_2.dart'; // Import data_table_2
import 'package:player_debug_adb/process_list_dialog.dart' as process_dialog; // Import the new dialog widget with a prefix

class LogcatPage extends StatefulWidget {
  final String deviceId;
  final String adbPath;

  const LogcatPage({
    Key? key,
    required this.deviceId,
    required this.adbPath,
  }) : super(key: key);

  @override
  _LogcatPageState createState() => _LogcatPageState();
}

class _LogcatPageState extends State<LogcatPage> {
  Process? _logcatProcess;
  final List<String> _logLines = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLogging = false;

  @override
  void initState() {
    super.initState();
    _startLogcat();
  }

  @override
  void dispose() {
    _stopLogcat();
    _scrollController.dispose();
    super.dispose();
  }




  void _stopLogcat() {
    if (!_isLogging) return;

    _logcatProcess?.kill();
    _logcatProcess = null;
    setState(() {
      _isLogging = false;
    });
  }

  void _resetLogcat() {
    _stopLogcat();
    _startLogcat();
  }

  void _clearLogcat() {
    setState(() {
      _logLines.clear();
    });
  }

  Future<void> _showTimeRangeDialog() async {
    String? selectedRange;
    TextEditingController customController = TextEditingController();

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择时间范围'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RadioListTile<String>(
                title: const Text('10分钟'),
                value: '10m',
                groupValue: selectedRange,
                onChanged: (value) {
                  selectedRange = value;
                  Navigator.of(context).pop(value);
                },
              ),
              RadioListTile<String>(
                title: const Text('30分钟'),
                value: '30m',
                groupValue: selectedRange,
                onChanged: (value) {
                  selectedRange = value;
                  Navigator.of(context).pop(value);
                },
              ),
              RadioListTile<String>(
                title: const Text('1小时'),
                value: '1h',
                groupValue: selectedRange,
                onChanged: (value) {
                  selectedRange = value;
                  Navigator.of(context).pop(value);
                },
              ),
              RadioListTile<String>(
                title: const Text('1天'),
                value: '1d',
                groupValue: selectedRange,
                onChanged: (value) {
                  selectedRange = value;
                  Navigator.of(context).pop(value);
                },
              ),
              ListTile(
                title: const Text('自定义 (例如: 10m, 1h, 1d)'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    controller: customController,
                    decoration: const InputDecoration(
                      hintText: '例如: 5m',
                    ),
                  ),
                ),
                onTap: () {
                  // Allow typing in the text field
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('确定'),
              onPressed: () {
                if (customController.text.isNotEmpty) {
                  Navigator.of(context).pop(customController.text);
                } else if (selectedRange != null) {
                   Navigator.of(context).pop(selectedRange);
                } else {
                   Navigator.of(context).pop(); // Close without selection
                }
              },
            ),
          ],
        );
      },
    ).then((result) {
      if (result != null && result.isNotEmpty) {
        _stopLogcat(); // Stop current process first
        _startLogcat(timeRange: result); // Start time-filtered process
      }
    });
  }

  Future<void> _showPidFilterDialog({String? initialPid}) async {
    TextEditingController pidController = TextEditingController();
    if (initialPid != null) {
      pidController.text = initialPid; // Set initial value if provided
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('根据进程PID查询日志'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pidController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '输入进程PID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16.0), // Add some spacing
              ElevatedButton( // Button to show running processes
                onPressed: () async {
                  // Close the current dialog first
                  Navigator.of(context).pop();
                  // Show the running processes dialog and wait for a result (PID)
                  final selectedPid = await _showRunningProcessesDialog();
                  // If a PID was selected, reopen the PID filter dialog and populate the input field
                  if (selectedPid != null) {
                    // Use addPostFrameCallback to ensure the dialog is built before showing again
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                       _showPidFilterDialog(initialPid: selectedPid); // Pass the selected PID
                    });
                  }
                },
                child: const Text('选择正在运行的进程'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('确定'),
              onPressed: () {
                final pid = pidController.text.trim();
                if (pid.isNotEmpty) {
                  // Validate if PID is a number
                  if (int.tryParse(pid) != null) {
                    _stopLogcat(); // Stop current logcat
                    _startLogcat(pid: pid); // Start logcat with PID filter
                    Navigator.of(context).pop(); // Close dialog
                  } else {
                    // Show error for invalid PID
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请输入有效的进程PID')),
                    );
                  }
                } else {
                   // If PID is empty, maybe show all logs or do nothing
                   // For now, let's just close the dialog
                   Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Remove the duplicate _startLogcat method definition
  // Future<void> _startLogcat({String? timeRange, String? pid}) async {
  //   if (_isLogging && timeRange == null && pid == null) return; // Prevent starting continuous log if already logging without filter
  //
  //   // If timeRange or pid is provided, we always start a new process
  //   if (timeRange != null || pid != null) {
  //      _stopLogcat(); // Ensure any existing process is stopped
  //   }
  //
  //   setState(() {
  //     _isLogging = true; // Temporarily set to true while starting
  //     _logLines.clear(); // Clear logs on start/restart
  //   });
  //
  //   try {
  //     List<String> args = ['-s', widget.deviceId, 'logcat'];
  //     if (timeRange != null && timeRange.isNotEmpty) {
  //       // adb logcat -t <time> format
  //       // Need to figure out the exact format for time range filtering
  //       // A common way is to filter by time, but filtering by duration is less direct.
  //       // Let's assume the user provides a duration like '10m', '1h', '1d'
  //       // We might need to calculate the start time based on the current time and the duration.
  //       // adb logcat -t 'MM-DD HH:MM:SS.ms'
  //       // Or maybe use -T <time> for logs newer than time
  //       // adb logcat -T 'MM-DD HH:MM:SS.ms'
  //
  //       // For simplicity, let's assume the user provides a format compatible with -T or -t if needed.
  //       // A more robust solution would involve calculating the timestamp.
  //       // For now, let's just add a placeholder argument.
  //       // Note: adb logcat time filtering by duration directly is not a standard feature.
  //       // Filtering by time requires calculating the start timestamp.
  //       // Example: adb logcat -T '01-20 10:00:00.000'
  //
  //       // Let's implement filtering by calculating the start time based on duration.
  //       DateTime startTime = DateTime.now();
  //       if (timeRange.endsWith('m')) {
  //         int minutes = int.parse(timeRange.replaceAll('m', ''));
  //         startTime = startTime.subtract(Duration(minutes: minutes));
  //       } else if (timeRange.endsWith('h')) {
  //         int hours = int.parse(timeRange.replaceAll('h', ''));
  //         startTime = startTime.subtract(Duration(hours: hours));
  //       } else if (timeRange.endsWith('d')) {
  //         int days = int.parse(timeRange.replaceAll('d', ''));
  //         startTime = startTime.subtract(Duration(days: days));
  //       } else {
  //          // Assume it's a custom timestamp format or handle error
  //          debugPrint('Unsupported time range format: $timeRange');
  //          // Fallback to no time filtering or show error to user
  //       }
  //
  //       // Format the start time for adb logcat -T 'MM-DD HH:MM:SS.ms'
  //       String formattedStartTime = "${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')} ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:${startTime.second.toString().padLeft(2, '0')}.${startTime.millisecond.toString().padLeft(3, '0')}";
  //       args.addAll(['-T', formattedStartTime]);
  //     }
  //
  //     if (pid != null && pid.isNotEmpty) {
  //       args.addAll(['--pid', pid]); // Add PID filter argument
  //     }
  //
  //     _logcatProcess = await Process.start(
  //       widget.adbPath,
  //       args,
  //       runInShell: true,
  //     );
  //
  //     // Listen to stdout
  //     _logcatProcess!.stdout.transform(utf8.decoder).listen(
  //       (data) {
  //         setState(() {
  //           _logLines.addAll(data.split('\n').where((line) => line.isNotEmpty));
  //         });
  //         // Scroll to the bottom
  //         WidgetsBinding.instance.addPostFrameCallback((_) {
  //           if (_scrollController.hasClients) {
  //             _scrollController.animateTo(
  //               _scrollController.position.maxScrollExtent,
  //               duration: const Duration(milliseconds: 100),
  //               curve: Curves.easeOut,
  //             );
  //           }
  //         });
  //       },
  //       onError: (e) {
  //         debugPrint('Logcat stdout error: $e');
  //         _stopLogcat();
  //       },
  //       onDone: () {
  //         debugPrint('Logcat stdout done.');
  //         _stopLogcat(); // Stop logging when the process is done
  //       },
  //     );
  //
  //     // Listen to stderr (optional, logcat usually outputs to stdout)
  //     _logcatProcess!.stderr.transform(utf8.decoder).listen(
  //       (data) {
  //         debugPrint('Logcat stderr: $data');
  //       },
  //       onError: (e) {
  //         debugPrint('Logcat stderr error: $e');
  //       },
  //     );
  //
  //     // Listen for process exit
  //     _logcatProcess!.exitCode.then((code) {
  //       debugPrint('Logcat process exited with code $code');
  //       _stopLogcat(); // Stop logging when the process exits
  //     });
  //
  //   } catch (e) {
  //     debugPrint('Failed to start logcat: $e');
  //     setState(() {
  //       _isLogging = false;
  //     });
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deviceId} 实时日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _showTimeRangeDialog,
            tooltip: '查看临近日志',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list), // New button for PID filter
            onPressed: _showPidFilterDialog, // Call a new method to show PID filter dialog
            tooltip: '根据进程PID查询日志',
          ),
          IconButton(
            icon: Icon(_isLogging ? Icons.stop : Icons.play_arrow),
            onPressed: _isLogging ? _stopLogcat : _startLogcat, // Use _startLogcat without timeRange for continuous
            tooltip: _isLogging ? '停止日志' : '开始日志',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetLogcat,
            tooltip: '重置日志',
          ),
          IconButton(
            icon: const Icon(Icons.clear), // 使用清除图标
            onPressed: _clearLogcat, // 调用清空日志方法
            tooltip: '清空日志',
          ),
          IconButton(
            icon: const Icon(Icons.list), // 使用列表图标
            onPressed: _showRunningProcessesDialog, // 调用显示进程列表方法
            tooltip: '查看正在运行的进程',
          ),
        ],
      ),
      body: ListView.builder(
        controller: _scrollController,
        itemCount: _logLines.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
            child: Text(
              _logLines[index],
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.0),
            ),
          );
        },
      ),
    );
  }


}