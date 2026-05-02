/// Web platform — no dart:io, no QR scanner, no Tailscale detection.
const kIsWeb = true;
const supportsQrScanning = false;

Future<String?> getTailscaleIP() async => null;
