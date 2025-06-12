import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:process_run/shell.dart';
import 'package:data_table_2/data_table_2.dart'; // Import data_table_2
import 'package:player_debug_adb/process_list_dialog.dart'
    as process_dialog; // Import the new dialog widget with a prefix

class LogcatPage extends StatefulWidget {
  final String deviceId;
  final String adbPath;

  const LogcatPage({Key? key, required this.deviceId, required this.adbPath})
    : super(key: key);

  @override
  _LogcatPageState createState() => _LogcatPageState();
}

enum LogViewTarget { global, application }

class _LogcatPageState extends State<LogcatPage> {
  Process? _logcatProcess;
  StreamSubscription<String>? _logcatProcessStdoutListen;
  StreamSubscription<String>? _logcatProcessStderrListen;
  final List<String> _logLines = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLogging = false;

  /// 用户是否手动滑动滚动条
  bool _useMoveScroll = false;

  /// 是否更新日志
  bool _isUpdateLog = false;
  LogViewTarget _currentLogViewTarget = LogViewTarget.global;
  Map<String, String>?
  _currentProcessInfo; // Store PID and Name for application view
  String? _currentTimeRange; // Store the current time range filter

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      // 如果滚动条不在最底部，并且用户正在滚动，则设置 _useMoveScroll 为 true
      if (_scrollController.position.pixels <
          _scrollController.position.maxScrollExtent) {
        if (!_useMoveScroll) {
          setState(() {
            _useMoveScroll = true;
          });
        }
      } else {
        // 如果滚动条在最底部，则重置 _useMoveScroll 为 false，允许自动滚动
        if (_useMoveScroll) {
          setState(() {
            _useMoveScroll = false;
          });
        }
      }
    });
    _startLogcat();
  }

  @override
  void dispose() {
    _stopLogcat();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _stopLogcat() async {
    if (!_isLogging) return;

    setState(() {
      _isLogging = false;
    });

    await _logcatProcessStdoutListen?.cancel();
    await _logcatProcessStderrListen?.cancel();
    _logcatProcess?.kill();
    _logcatProcess = null;
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
    TextEditingController customController = TextEditingController();

    String? dialogSelectedRange = _currentTimeRange;
    if (_currentTimeRange != null &&
        !['10m', '30m', '1h', '1d'].contains(_currentTimeRange)) {
      customController.text = _currentTimeRange!;
    }

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择时间范围'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateDialog) {
              // Renamed setState to setStateDialog for clarity
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  RadioListTile<String>(
                    title: const Text('10分钟'),
                    value: '10m',
                    groupValue: dialogSelectedRange,
                    onChanged: (value) {
                      setStateDialog(() {
                        // Use setStateDialog here
                        dialogSelectedRange = value;
                        customController
                            .clear(); // Clear custom input when a radio button is selected
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('30分钟'),
                    value: '30m',
                    groupValue: dialogSelectedRange,
                    onChanged: (value) {
                      setStateDialog(() {
                        // Use setStateDialog here
                        dialogSelectedRange = value;
                        customController.clear();
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('1小时'),
                    value: '1h',
                    groupValue: dialogSelectedRange,
                    onChanged: (value) {
                      setStateDialog(() {
                        // Use setStateDialog here
                        dialogSelectedRange = value;
                        customController.clear();
                      });
                    },
                  ),
                  RadioListTile<String>(
                    title: const Text('1天'),
                    value: '1d',
                    groupValue: dialogSelectedRange,
                    onChanged: (value) {
                      setStateDialog(() {
                        // Use setStateDialog here
                        dialogSelectedRange = value;
                        customController.clear();
                      });
                    },
                  ),
                  ListTile(
                    title: const Text('自定义 (例如: 10m, 1h, 1d)'),
                    trailing: SizedBox(
                      width: 100,
                      child: TextField(
                        controller: customController,
                        decoration: const InputDecoration(hintText: '例如: 5m'),
                        onChanged: (value) {
                          if (value.isNotEmpty) {
                            setStateDialog(() {
                              // Use setStateDialog here
                              dialogSelectedRange =
                                  null; // Clear radio selection when custom input is used
                            });
                          }
                        },
                      ),
                    ),
                    onTap: () {
                      // Allow typing in the text field
                    },
                  ),
                ],
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('清除筛选'),
              onPressed: () {
                Navigator.of(context).pop(''); // Pass empty string to clear
              },
            ),
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
                } else if (dialogSelectedRange != null) {
                  Navigator.of(context).pop(dialogSelectedRange);
                } else {
                  Navigator.of(
                    context,
                  ).pop(); // No change or clear if nothing selected
                }
              },
            ),
          ],
        );
      },
    ).then((result) {
      if (result != null) {
        // Allow empty string to clear filter
        _stopLogcat();
        setState(() {
          _currentTimeRange = result.isEmpty ? null : result;
        });
        _startLogcat(); // Restart with new or cleared time range
      }
    });
  }

  Future<void> _showPidFilterDialog({String? initialPid}) async {
    TextEditingController pidController = TextEditingController();
    if (initialPid != null) {
      pidController.text = initialPid; // Set initial value if provided
    }

    bool isLoadingProcesses = false;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
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
                  ElevatedButton(
                    onPressed: isLoadingProcesses
                        ? null // Disable button when loading
                        : () async {
                            setStateDialog(() {
                              isLoadingProcesses = true;
                            });
                            // Show the running processes dialog and wait for a result (PID)
                            final selectedPid =
                                await _showRunningProcessesDialog();
                            // If a PID was selected, update the PID text field in the current dialog
                            if (selectedPid != null) {
                              pidController.text = selectedPid;
                            }
                            setStateDialog(() {
                              isLoadingProcesses = false;
                            });
                          },
                    child: isLoadingProcesses
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('选择正在运行的进程'),
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
                  onPressed: () async {
                    // Make this async to await _getProcessNameFromPid
                    final pid = pidController.text.trim();
                    if (pid.isNotEmpty) {
                      if (int.tryParse(pid) != null) {
                        final processName = await _getProcessNameFromPid(pid);
                        setState(() {
                          _currentLogViewTarget = LogViewTarget.application;
                          _currentProcessInfo = {
                            'PID': pid,
                            'NAME': processName ?? 'App (PID: $pid)',
                          };
                        });
                        _resetLogcat(); // This will use the new _currentProcessInfo
                        Navigator.of(context).pop(); // Close dialog
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入有效的进程PID')),
                        );
                      }
                    } else {
                      // If PID is empty, switch to global log
                      setState(() {
                        _currentLogViewTarget = LogViewTarget.global;
                        _currentProcessInfo = null;
                      });
                      _resetLogcat();
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showRunningProcessesDialog({
    bool isForSelection = false,
  }) async {
    var shell = Shell();
    try {
      // Execute adb shell ps -A to get all running processes
      var result = await shell.run('''
        ${widget.adbPath} -s ${widget.deviceId} shell ps -A
      ''');

      if (result.isNotEmpty && result[0].exitCode == 0) {
        var stdout = result[0].stdout as String;
        var lines = stdout.split('\n');
        if (lines.length < 2) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法解析进程列表')));
          return null;
        }

        // Extract headers and process data
        var headers = lines[0].trim().split(RegExp(r'\s+'));
        var processes = lines
            .sublist(1)
            .where((line) => line.trim().isNotEmpty)
            .map((line) {
              return line.trim().split(RegExp(r'\s+'));
            })
            .toList();

        if (!mounted) return null;
        return await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('选择一个进程'),
              content: SizedBox(
                width:
                    MediaQuery.of(context).size.width *
                    0.8, // 80% of screen width
                height:
                    MediaQuery.of(context).size.height *
                    0.6, // 60% of screen height
                child: process_dialog.ProcessListDialog(
                  processes: processes,
                  headers: headers,
                  // adbPath: widget.adbPath,
                  // deviceId: widget.deviceId,
                  onProcessSelected: isForSelection
                      ? (pid) => Navigator.of(context).pop(pid)
                      : null,
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('取消'),
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop(); // Close without returning a PID
                  },
                ),
              ],
            );
          },
        );
      } else {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '获取进程列表失败: ${result.isNotEmpty ? result[0].stderr : "Unknown error"}',
            ),
          ),
        );
        return null;
      }
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('执行命令时出错: $e')));
      return null;
    }
  }

  Future<void> _startLogcat({bool forceGlobal = false}) async {
    // If forceGlobal is true, or current view is global, use the provided pid or no pid.
    // If current view is application, use the _currentProcessInfo's PID.
    String? targetPid;
    if (!forceGlobal &&
        _currentLogViewTarget == LogViewTarget.application &&
        _currentProcessInfo != null) {
      targetPid = _currentProcessInfo!['PID'];
    }

    // Use _currentTimeRange if set
    final timeRange = _currentTimeRange;

    if (_isLogging && timeRange == null && targetPid == null && !forceGlobal) {
      return; // Prevent starting continuous log if already logging without filter and not forcing global
    }

    // If timeRange or pid is provided, or if switching view target, we always start a new process
    if (timeRange != null ||
        targetPid != null ||
        forceGlobal ||
        (_currentLogViewTarget == LogViewTarget.global &&
            _currentProcessInfo != null) ||
        (_currentLogViewTarget == LogViewTarget.application &&
            _currentProcessInfo == null)) {
      _stopLogcat(); // Ensure any existing process is stopped
    }

    setState(() {
      _isLogging = true; // Temporarily set to true while starting
      _logLines.clear(); // Clear logs on start/restart
    });

    try {
      List<String> args = ['-s', widget.deviceId, 'logcat'];
      bool isTimeFiltered = (timeRange != null && timeRange.isNotEmpty);

      if (isTimeFiltered) {
        // If time range is specified, use -d to dump and exit
        args.add('-d');

        DateTime startTime = DateTime.now();
        if (timeRange!.endsWith('m')) {
          int minutes = int.parse(timeRange.replaceAll('m', ''));
          startTime = startTime.subtract(Duration(minutes: minutes));
        } else if (timeRange.endsWith('h')) {
          int hours = int.parse(timeRange.replaceAll('h', ''));
          startTime = startTime.subtract(Duration(hours: hours));
        } else if (timeRange.endsWith('d')) {
          int days = int.parse(timeRange.replaceAll('d', ''));
          startTime = startTime.subtract(Duration(days: days));
        } else {
          debugPrint('Unsupported time range format: $timeRange');
        }

        String formattedStartTime =
            "${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')} ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}:${startTime.second.toString().padLeft(2, '0')}.${startTime.millisecond.toString().padLeft(3, '0')}";
        args.addAll(['-T', formattedStartTime]);
      }

      if (targetPid != null && targetPid.isNotEmpty) {
        args.addAll(['--pid', targetPid]); // Add PID filter argument
      }

      _logcatProcess = await Process.start(
        widget.adbPath,
        args,
        runInShell: false,
      );

      debugPrint("adb args = ${args.join(" ")}");
      // Listen to stdout and stderr
      _logcatProcessStdoutListen = _logcatProcess?.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              setState(() {
                _logLines.add(line);
              });
            },
            onDone: () {
              if (isTimeFiltered) {
                _stopLogcat(); // Stop the process when done for time-filtered logs
              }
            },
            onError: (error) {
              debugPrint('Logcat stdout error: $error');
              if (isTimeFiltered) {
                _stopLogcat();
              }
            },
          );
      _logcatProcessStderrListen = _logcatProcess?.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              debugPrint('Logcat stderr: $line');
            },
            onError: (error) {
              debugPrint('Logcat stderr error: $error');
            },
          );

      // Listen for process exit
      _logcatProcess!.exitCode.then((code) {
        debugPrint('Logcat process exited with code $code');
        _stopLogcat(); // Stop logging when the process exits
      });
    } catch (e) {
      debugPrint('Failed to start logcat: $e');
      setState(() {
        _isLogging = false;
      });
    }

    //Scroll to the bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (_isUpdateLog) {
          _isUpdateLog = false;
          return;
        }

        if (!_useMoveScroll && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  // Helper to get process name from PID (placeholder, needs implementation)
  Future<String?> _getProcessNameFromPid(String pid) async {
    // This is a placeholder. You would need to run a command like:
    // adb shell ps -A | grep <PID>
    // And parse the output to get the process name.
    // For simplicity, returning a placeholder or the PID itself.
    var shell = Shell();
    try {
      String command;
      if (Platform.isWindows) {
        command =
            '${widget.adbPath} -s ${widget.deviceId} shell ps -A | findstr $pid';
      } else {
        command =
            '${widget.adbPath} -s ${widget.deviceId} shell ps -A | grep $pid';
      }
      var result = await shell.run(command);
      if (result.isNotEmpty && result[0].exitCode == 0) {
        var stdout = result[0].stdout as String;
        var lines = stdout.split('\n');
        if (lines.isNotEmpty) {
          var parts = lines[0].trim().split(RegExp(r'\s+'));
          if (parts.length > 8) {
            // Assuming NAME is the 9th column (index 8)
            return parts[8];
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting process name for PID $pid: $e');
    }
    return null; // Fallback, indicates name not found
  }

  Future<void> _exportLogs() async {
    String deviceIdentifier = widget.deviceId.replaceAll(
      RegExp(r'[\.\:]'),
      '_',
    );

    // Generate default file name
    final String timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final String defaultFileName =
        'Mooncell设备-$deviceIdentifier-$timestamp.txt';

    String? initialDirectory;
    try {
      final directory = await getApplicationDocumentsDirectory();
      initialDirectory = directory.path;
    } catch (e) {
      print('Could not get downloads directory: $e');
    }

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '选择日志保存路径',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['txt'],
      initialDirectory: initialDirectory,
    );

    if (outputFile == null) {
      // User canceled the picker
      return;
    }

    try {
      final File file = File(outputFile);
      await file.writeAsString(_logLines.join('\n'));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('日志已成功导出到: $outputFile')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出日志失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    String deviceName = widget.deviceId;
    List<Widget> titleWidgets = [
      Text(deviceName),
      const SizedBox(width: 8),
      const Text('实时日志'),
    ];

    List<Widget> statusWidgets = [];
    if (_currentLogViewTarget == LogViewTarget.application &&
        _currentProcessInfo != null) {
      final name = _currentProcessInfo!['NAME'];
      final pid = _currentProcessInfo!['PID'];
      String appInfo;
      if (name != null && name.isNotEmpty && name != 'App (PID: $pid)') {
        appInfo = '应用: $name (PID: $pid)';
      } else {
        appInfo = '应用: (PID: $pid)';
      }
      statusWidgets.add(Chip(label: Text(appInfo)));
    }

    if (_currentTimeRange != null && _currentTimeRange!.isNotEmpty) {
      statusWidgets.add(Chip(label: Text('时间范围: $_currentTimeRange')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8.0, // spacing between title elements
          children: titleWidgets,
        ),
        actions: <Widget>[
          IconButton(
            icon: _isLogging
                ? const Icon(Icons.pause_circle_filled_rounded)
                : const Icon(Icons.play_circle_outline_rounded),
            tooltip: _isLogging ? '暂停' : '继续',
            onPressed: () {
              if (_isLogging) {
                _stopLogcat();
              } else {
                _startLogcat();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重置',
            onPressed: _resetLogcat,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: '清空',
            onPressed: _clearLogcat,
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: '按时间范围过滤',
            onPressed: _showTimeRangeDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: '按PID过滤',
            onPressed: () => _showPidFilterDialog(),
          ),
          PopupMenuButton<LogViewTarget>(
            tooltip: '选择日志查看对象',
            onSelected: (LogViewTarget result) async {
              if (result == LogViewTarget.application) {
                _showPidFilterDialog();
              } else {
                setState(() {
                  _currentLogViewTarget = LogViewTarget.global;
                  _currentProcessInfo = null;
                });
                _resetLogcat();
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<LogViewTarget>>[
                  const PopupMenuItem<LogViewTarget>(
                    value: LogViewTarget.global,
                    child: Text('全局日志'),
                  ),
                  const PopupMenuItem<LogViewTarget>(
                    value: LogViewTarget.application,
                    child: Text('应用日志 (PID)'),
                  ),
                ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (statusWidgets.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8.0),
              color:
                  Theme.of(
                    context,
                  ).chipTheme.backgroundColor?.withOpacity(0.1) ??
                  Theme.of(context).colorScheme.surfaceVariant,
              child: Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                alignment: WrapAlignment.start,
                children: statusWidgets,
              ),
            ), // Close the Wrap widget
          // Add the export button below the Wrap widget
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _exportLogs,
                icon: const Icon(Icons.download),
                label: const Text('导出日志'),
              ),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: Container(
                color: Colors.black,
                child: ScrollbarTheme(
                  data: ScrollbarThemeData(
                    thumbColor: WidgetStateProperty.all(Colors.grey),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logLines.length,
                    itemBuilder: (context, index) {
                      return Text(
                        _logLines[index],
                        style: const TextStyle(
                          fontSize: 14.0,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
