import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/paired_device.dart';

class DeviceStorage {
  static const _devicesKey = 'paired_devices';

  static Future<List<PairedDevice>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_devicesKey);
    if (raw == null) return [];
    return raw
        .map((s) {
          try {
            return PairedDevice.fromJson(jsonDecode(s) as Map<String, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<PairedDevice>()
        .toList();
  }

  static Future<void> saveDevice(PairedDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await loadDevices();
    final idx = devices.indexWhere((d) => d.agentId == device.agentId);
    if (idx >= 0) {
      devices[idx] = device;
    } else {
      devices.add(device);
    }
    await prefs.setStringList(
      _devicesKey,
      devices.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }

  static Future<void> removeDevice(String agentId) async {
    final prefs = await SharedPreferences.getInstance();
    final devices = await loadDevices();
    devices.removeWhere((d) => d.agentId == agentId);
    await prefs.setStringList(
      _devicesKey,
      devices.map((d) => jsonEncode(d.toJson())).toList(),
    );
  }
}
