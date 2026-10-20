import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Kullanıcıya sesli (Faz 10: Türkçe TTS) ve dokunsal geri bildirim.
/// Arayüz: testlerde sahtesi kullanılır.
abstract class GeriBildirimci {
  Future<void> soyle(String metin);
  Future<void> sustur();
  void titresim(Titresim tur);
}

enum Titresim { basla, birak, kabul, red, acil }

/// Telefonun kendi Türkçe sesi (iOS AVSpeechSynthesizer / Android TextToSpeech)
/// ve titreşim motoru (HapticFeedback). Türkçe ses paketi cihazda yoksa
/// sessizce yalnızca titreşim çalışır.
class CihazGeriBildirimci implements GeriBildirimci {
  CihazGeriBildirimci({this.sesAcik = true, this.titresimAcik = true}) {
    _tts.setLanguage('tr-TR');
    _tts.setSpeechRate(0.55);
    _tts.awaitSpeakCompletion(false);
  }

  final FlutterTts _tts = FlutterTts();
  bool sesAcik;
  bool titresimAcik;

  @override
  Future<void> soyle(String metin) async {
    if (!sesAcik || metin.isEmpty) return;
    await _tts.stop(); // yeni haber eskisini keser: telsizde sıra beklemek yok
    await _tts.speak(metin);
  }

  @override
  Future<void> sustur() async => _tts.stop();

  @override
  void titresim(Titresim tur) {
    if (!titresimAcik) return;
    switch (tur) {
      case Titresim.basla:
        HapticFeedback.mediumImpact();
      case Titresim.birak:
        HapticFeedback.lightImpact();
      case Titresim.kabul:
        HapticFeedback.selectionClick();
      case Titresim.red:
        HapticFeedback.heavyImpact();
      case Titresim.acil:
        HapticFeedback.vibrate();
    }
  }
}
