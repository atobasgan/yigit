import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../protokol/mesajlar.dart';

/// Ham PCM kaynağı (testlerde sahtesi kullanılır).
abstract class SesKaynagi {
  bool get acik;
  Future<bool> izinIste();

  /// 16 kHz mono PCM16 akışını başlatır; her parça [veri]'ye gelir.
  Future<void> ac(void Function(Uint8List veri) veri, {bool gurultuBastirma});
  Future<void> kapat();
}

/// `record` paketi ile mikrofon. Android'de VOICE_RECOGNITION kaynağı
/// (tanıma için ayarlanmış, düz frekans yanıtı) kullanılır.
class Mikrofon implements SesKaynagi {
  final AudioRecorder _kayitci = AudioRecorder();
  StreamSubscription<Uint8List>? _abonelik;

  @override
  bool get acik => _abonelik != null;

  @override
  Future<bool> izinIste() => _kayitci.hasPermission();

  @override
  Future<void> ac(void Function(Uint8List veri) veri, {bool gurultuBastirma = false}) async {
    if (acik) return;
    final akis = await _kayitci.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: orneklemeHz,
        numChannels: 1,
        noiseSuppress: gurultuBastirma,
        androidConfig: const AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
      ),
    );
    _abonelik = akis.listen(veri);
  }

  @override
  Future<void> kapat() async {
    await _abonelik?.cancel();
    _abonelik = null;
    await _kayitci.stop();
  }

  Future<void> dispose() async {
    await kapat();
    await _kayitci.dispose();
  }
}
