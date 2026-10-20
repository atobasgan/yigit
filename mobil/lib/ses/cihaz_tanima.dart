import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Drone sözlüğü: tanıyıcıyı bu kelimelere yatkınlaştırır (Whisper'daki
/// initial_prompt'un karşılığı; destekleyen platformlarda kullanılır).
const droneSozlugu = [
  'kalk',
  'kalkış yap',
  'in',
  'iniş yap',
  'yüksel',
  'alçal',
  'metre',
  'metreye çık',
  'ileri',
  'geri',
  'sağa',
  'sola',
  'dön',
  'derece',
  'kuzeye',
  'güneye',
  'doğuya',
  'batıya',
  'dur',
  'bekle',
  'saniye',
  'eve dön',
  'en yakın hastane',
];

class TanimaSonucu {
  const TanimaSonucu(this.metin, this.guven);
  final String metin;
  final double? guven;
}

/// Telefonun kendi konuşma tanıyıcısı (testlerde sahtesi kullanılır).
abstract class CihazTanima {
  Future<bool> hazirla();

  /// Dinlemeye başlar; ara sonuçlar [kismi]'ye gelir.
  Future<void> basla({required String dil, required bool cevrimdisi, void Function(String)? kismi});

  /// Dinlemeyi bitirir ve son sonucu bekler (en fazla [bekle]).
  Future<TanimaSonucu?> bitir({Duration bekle});
  Future<void> iptal();
}

/// `speech_to_text` paketi: Android SpeechRecognizer / iOS SFSpeechRecognizer.
/// Türkçe (tr-TR) cihaz üstü desteği cihaza bağlıdır; [cevrimdisi] true ise
/// internetsiz tanıma istenir (cihaz desteklemiyorsa hata verebilir).
class SistemTanima implements CihazTanima {
  final SpeechToText _stt = SpeechToText();
  SpeechRecognitionResult? _son;
  Completer<void>? _final;
  String? _hata;

  @override
  Future<bool> hazirla() => _stt.initialize(
    onError: (e) {
      _hata = e.errorMsg;
      _final?.complete();
    },
    onStatus: (durum) {
      if (durum == SpeechToText.doneStatus) _final?.complete();
    },
  );

  @override
  Future<void> basla({required String dil, required bool cevrimdisi, void Function(String)? kismi}) async {
    _son = null;
    _hata = null;
    _final = Completer<void>();
    await _stt.listen(
      onResult: (r) {
        _son = r;
        kismi?.call(r.recognizedWords);
        if (r.finalResult && !(_final?.isCompleted ?? true)) _final!.complete();
      },
      listenOptions: SpeechListenOptions(
        localeId: dil,
        onDevice: cevrimdisi,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
        // Bas-konuşta bitişi tuş belirler; sessizlikte kendiliğinden kesmesin.
        pauseFor: const Duration(seconds: 15),
        listenFor: const Duration(seconds: 20),
        contextualPhrases: droneSozlugu,
      ),
    );
  }

  @override
  Future<TanimaSonucu?> bitir({Duration bekle = const Duration(milliseconds: 1500)}) async {
    await _stt.stop();
    final f = _final;
    if (f != null && !f.isCompleted) {
      await f.future.timeout(bekle, onTimeout: () {});
    }
    final r = _son;
    if (r == null || r.recognizedWords.trim().isEmpty) {
      if (_hata != null) throw StateError(_hata!);
      return null;
    }
    return TanimaSonucu(r.recognizedWords, r.hasConfidenceRating ? r.confidence : null);
  }

  @override
  Future<void> iptal() => _stt.cancel();
}
