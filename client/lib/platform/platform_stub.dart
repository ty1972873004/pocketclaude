/// Stub platform detection — overridden by platform_io and platform_web.
const kIsWeb = false;
const supportsQrScanning = true;

Future<String?> getTailscaleIP() async => null;
