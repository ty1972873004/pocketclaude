import 'dart:io';

/// IO (native) platform — mobile and desktop.
const kIsWeb = false;
const supportsQrScanning = true;

Future<String?> getTailscaleIP() async {
  try {
    for (final interface in await NetworkInterface.list()) {
      for (final addr in interface.addresses) {
        final ip = addr.address;
        final parts = ip.split('.');
        if (parts.length == 4) {
          final first = int.tryParse(parts[0]) ?? 0;
          final second = int.tryParse(parts[1]) ?? 0;
          if (first == 100 && second >= 64 && second <= 127) {
            return ip;
          }
        }
      }
    }
  } catch (_) {}
  return null;
}
