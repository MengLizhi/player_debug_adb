import 'package:flutter/material.dart';

class AdbManager {
  static final AdbManager _instance = AdbManager._internal();
  factory AdbManager() => _instance;
  AdbManager._internal();

  String? _adbPath;

  String? get adbPath => _adbPath;
  set adbPath(String? path) {
    _adbPath = path;
  }

  bool get isAdbPathSet => _adbPath != null;
}