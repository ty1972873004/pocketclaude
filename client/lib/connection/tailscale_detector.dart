import '../platform/platform.dart';

/// Detects whether the device has an active Tailscale interface.
class TailscaleDetector {
  /// Returns the Tailscale IP if found, null otherwise.
  static Future<String?> detectTailscaleIP() => getTailscaleIP();

  /// Checks if the device has any Tailscale interface.
  static Future<bool> hasTailscale() async => await detectTailscaleIP() != null;

  /// Checks if a given IP looks like a Tailscale IP (100.64.0.0/10).
  static bool isTailscaleIP(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    try {
      final first = int.parse(parts[0]);
      final second = int.parse(parts[1]);
      if (first != 100) return false;
      return second >= 64 && second <= 127;
    } catch (_) {
      return false;
    }
  }
}
