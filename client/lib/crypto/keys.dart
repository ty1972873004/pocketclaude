import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class KeyPair {
  final Uint8List publicKey;
  final Uint8List privateKey;

  KeyPair({required this.publicKey, required this.privateKey});
}

class CryptoService {
  static const _keySize = 32;

  /// Generate X25519 key pair for key exchange
  static KeyPair generateX25519KeyPair() {
    final secureRandom = FortunaRandom();
    final seeds = List<int>.generate(32, (_) => DateTime.now().millisecondsSinceEpoch);
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = KeyGenerator('X25519');
    final params = X25519KeyGenerationParameters(secureRandom);
    keyGen.init(params);

    final pair = keyGen.generateKeyPair();
    return KeyPair(
      publicKey: (pair.publicKey as X25519PublicKey).Q!,
      privateKey: (pair.privateKey as X25519PrivateKey).d!,
    );
  }

  /// Generate Ed25519 key pair for signing
  static KeyPair generateEd25519KeyPair() {
    final secureRandom = FortunaRandom();
    final seeds = List<int>.generate(32, (_) => DateTime.now().millisecondsSinceEpoch);
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = KeyGenerator('Ed25519');
    final params = Ed25519KeyGenerationParameters(secureRandom);
    keyGen.init(params);

    final pair = keyGen.generateKeyPair();
    return KeyPair(
      publicKey: (pair.publicKey as Ed25519PublicKey).Q!,
      privateKey: (pair.privateKey as Ed25519PrivateKey).d!,
    );
  }

  /// Derive shared secret using X25519 DH
  static Uint8List deriveSharedSecret(Uint8List myPrivateKey, Uint8List theirPublicKey) {
    final privateKey = X25519PrivateKey(Uint8List.fromList(myPrivateKey));
    final publicKey = X25519PublicKey(Uint8List.fromList(theirPublicKey));

    final agreement = KeyAgreement('X25519');
    agreement.init(PrivateKeyParameter<ECPrivateKey>(privateKey as ECPrivateKey));
    final sharedSecret = agreement.calculateAgreement(publicKey as ECPublicKey);
    return sharedSecret;
  }

  /// Get fingerprint of public key (SHA-256, first 8 bytes hex)
  static String getFingerprint(Uint8List publicKey) {
    final digest = SHA256Digest();
    final hash = digest.process(publicKey);
    return hash.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
  }
}
