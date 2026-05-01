import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../crypto/encryption.dart';
import '../../models/paired_device.dart';
import '../../storage/device_storage.dart';

class PairingPage extends ConsumerStatefulWidget {
  const PairingPage({super.key});

  @override
  ConsumerState<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends ConsumerState<PairingPage> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _scanning = true;
  bool _pairing = false;
  String? _error;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scanning) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    _scanning = false;
    _scannerController.stop();

    try {
      final data = jsonDecode(barcode.rawValue!) as Map<String, dynamic>;
      _pairWithAgent(data);
    } catch (e) {
      setState(() {
        _error = '无效的 QR 码: $e';
        _scanning = true;
      });
    }
  }

  Future<void> _pairWithAgent(Map<String, dynamic> data) async {
    setState(() => _pairing = true);

    try {
      final agentId = data['agent_id'] as String;
      final agentIP = data['agent_ip'] as String? ?? '127.0.0.1';
      final agentX25519PubKeyB64 = data['x25519_pub_key'] as String;
      final agentEd25519PubKeyB64 =
          data['ed25519_pub_key'] as String? ?? '';
      final relayUrl = data['relay_url'] as String? ?? '';
      final pairingPort = data['pairing_port'] as int;

      // 1. Generate client X25519 key pair
      final x25519 = crypto.X25519();
      final clientKeyPair = await x25519.newKeyPair();
      final clientPubKey = await clientKeyPair.extractPublicKey();
      final clientPrivKeyBytes =
          await clientKeyPair.extractPrivateKeyBytes();

      // 2. Derive shared secret using agent's X25519 public key
      final agentPubKeyBytes = base64Decode(agentX25519PubKeyB64);
      final agentPublicKey = crypto.SimplePublicKey(
        agentPubKeyBytes,
        type: crypto.KeyPairType.x25519,
      );
      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: clientKeyPair,
        remotePublicKey: agentPublicKey,
      );
      final sharedSecretBytes = await sharedSecret.extractBytes();

      // 3. Connect to agent's pairing WebSocket and send client public key
      final clientId = const Uuid().v4();
      final pairingUrl = 'ws://$agentIP:$pairingPort/pair';
      final wsChannel = WebSocketChannel.connect(Uri.parse(pairingUrl));

      final pairingMessage = jsonEncode({
        'client_id': clientId,
        'x25519_pub_key': base64Encode(clientPubKey.bytes),
        'ed25519_pub_key': '',
        'device_name': 'Phone',
        'signature': '',
      });

      wsChannel.sink.add(pairingMessage);

      // 4. Wait for confirmation
      final response = await wsChannel.stream.first
          .timeout(const Duration(seconds: 10));
      wsChannel.sink.close();

      final confirm = jsonDecode(response as String) as Map<String, dynamic>;
      if (confirm['status'] != 'paired') {
        throw Exception('Agent rejected pairing: ${confirm['status']}');
      }

      // 5. Save paired device
      final device = PairedDevice(
        agentId: agentId,
        agentIP: agentIP,
        relayUrl: relayUrl,
        agentX25519PubKey: agentX25519PubKeyB64,
        agentEd25519PubKey: agentEd25519PubKeyB64,
        clientX25519PubKey: base64Encode(clientPubKey.bytes),
        clientX25519PrivKey: base64Encode(clientPrivKeyBytes),
        sharedKeyBase64: base64Encode(sharedSecretBytes),
        deviceName: 'Dev Machine ($agentId.substring(0, 8))',
        pairedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await DeviceStorage.saveDevice(device);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('设备 ${device.deviceName} 配对成功！')),
        );
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '配对失败: $e';
          _pairing = false;
          _scanning = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加设备'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                ),
                _ScanOverlay(),
                if (_pairing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在配对...',
                              style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    '扫描开发机上的 QR 码',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在开发机上运行 pocketclaude-agent pair 生成 QR 码',
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _scanning = true;
                        });
                        _scannerController.start();
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScanOverlayPainter(),
      size: Size.infinite,
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scanSize = size.width * 0.7;
    final rect = Rect.fromCenter(
        center: center, width: scanSize, height: scanSize);

    final overlayPaint = Paint()..color = Colors.black54;
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)));
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, overlayPaint);

    final bracketPaint = Paint()
      ..color = const Color(0xFF6C63FF)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    const bracketLen = 24.0;

    canvas.drawLine(
        rect.topLeft, rect.topLeft.translate(bracketLen, 0), bracketPaint);
    canvas.drawLine(
        rect.topLeft, rect.topLeft.translate(0, bracketLen), bracketPaint);

    canvas.drawLine(rect.topRight,
        rect.topRight.translate(-bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.topRight,
        rect.topRight.translate(0, bracketLen), bracketPaint);

    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft.translate(bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.bottomLeft,
        rect.bottomLeft.translate(0, -bracketLen), bracketPaint);

    canvas.drawLine(rect.bottomRight,
        rect.bottomRight.translate(-bracketLen, 0), bracketPaint);
    canvas.drawLine(rect.bottomRight,
        rect.bottomRight.translate(0, -bracketLen), bracketPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
