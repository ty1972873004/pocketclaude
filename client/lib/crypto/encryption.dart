import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// EncryptionService matches the Go agent's E2ECipher wire format:
/// Wire: [8-byte big-endian nonce counter] + [AES-256-GCM ciphertext + tag]
class EncryptionService {
  final Uint8List _sharedKey;
  int _sendCounter = 0;
  int _recvCounter = 0;

  EncryptionService(this._sharedKey);

  /// Encrypt plaintext. Output: [8-byte counter][GCM ciphertext+tag]
  Uint8List encrypt(Uint8List plaintext) {
    final nonce = _nonceFromCounter(_sendCounter);
    _sendCounter++;

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(_sharedKey),
          128, // tag length in bits
          nonce,
          Uint8List(0),
        ),
      );

    final ciphertext = cipher.process(plaintext);

    // Wire format: [8-byte big-endian counter] + [ciphertext + tag]
    final result = Uint8List(8 + ciphertext.length);
    result[0] = (_sendCounter - 1) >> 56 & 0xFF;
    result[1] = (_sendCounter - 1) >> 48 & 0xFF;
    result[2] = (_sendCounter - 1) >> 40 & 0xFF;
    result[3] = (_sendCounter - 1) >> 32 & 0xFF;
    result[4] = (_sendCounter - 1) >> 24 & 0xFF;
    result[5] = (_sendCounter - 1) >> 16 & 0xFF;
    result[6] = (_sendCounter - 1) >> 8 & 0xFF;
    result[7] = (_sendCounter - 1) & 0xFF;
    result.setRange(8, result.length, ciphertext);

    return result;
  }

  /// Decrypt data in Go wire format: [8-byte counter][GCM ciphertext+tag]
  Uint8List decrypt(Uint8List data) {
    if (data.length < 8) throw ArgumentError('ciphertext too short');

    // Extract counter
    final counter = (data[0] << 56) |
        (data[1] << 48) |
        (data[2] << 40) |
        (data[3] << 32) |
        (data[4] << 24) |
        (data[5] << 16) |
        (data[6] << 8) |
        data[7];

    // Reconstruct nonce: [4 zero bytes][8-byte big-endian counter]
    final nonce = _nonceFromCounter(counter);
    _recvCounter = counter + 1;

    final ciphertext = data.sublist(8);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(_sharedKey),
          128,
          nonce,
          Uint8List(0),
        ),
      );

    return cipher.process(ciphertext);
  }

  /// Constructs a 12-byte nonce: [0,0,0,0][8-byte big-endian counter]
  /// This matches Go's binary.BigEndian.PutUint64(nonce[4:12], counter)
  Uint8List _nonceFromCounter(int counter) {
    final nonce = Uint8List(12);
    nonce[4] = (counter >> 56) & 0xFF;
    nonce[5] = (counter >> 48) & 0xFF;
    nonce[6] = (counter >> 40) & 0xFF;
    nonce[7] = (counter >> 32) & 0xFF;
    nonce[8] = (counter >> 24) & 0xFF;
    nonce[9] = (counter >> 16) & 0xFF;
    nonce[10] = (counter >> 8) & 0xFF;
    nonce[11] = counter & 0xFF;
    return nonce;
  }

  void resetCounters() {
    _sendCounter = 0;
    _recvCounter = 0;
  }
}
