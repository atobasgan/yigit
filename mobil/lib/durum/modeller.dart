/// Uygulamanın veri tipleri. Her fazda yenileri eklenecek.
library;

import 'dart:convert';

/// Bas-konuş tuşunun durumu.
enum PttDurumu {
  /// Tuş boşta, basılmayı bekliyor.
  bos,

  /// Tuşa basılı tutuluyor, ses alınıyor.
  dinliyor,

  /// Tuş bırakıldı, komut işleniyor.
  isleniyor,
}

/// Yer istasyonu bağlantısının durumu.
enum BaglantiDurumu { kopuk, baglaniyor, bagli, hata }

/// Bir konuşma kartının aşamaları (sunucudan gelen mesajlarla ilerler).
enum KartDurumu { dinleniyor, isleniyor, duyuldu, komut, yurutuyor, tamamlandi, reddedildi, anlasilmadi }

/// Bir komutun (yazılı ya da sesli) ekrandaki kartı.
class KonusmaKarti {
  KonusmaKarti({required this.id, required this.giris, DateTime? zaman}) : zaman = zaman ?? DateTime.now();

  final int id;

  /// ses | klavye | hizli_tus | uzak (başka operatörün)
  final String giris;
  final DateTime zaman;

  KartDurumu durum = KartDurumu.dinleniyor;
  String? duyulan; // telefonun gönderdiği / STT'nin duyduğu metin
  String? normalize; // command_parser'ın normalize ettiği metin
  int? sttMs;
  String? sttKaynagi; // klavye | hizli_tus | telefon_stt | yer_stt
  List<Map<String, dynamic>> adimlar = const [];
  String? komutKaynagi; // hizli_yol | llm | acil | onbellek
  bool kuyrugaEklendi = false;
  double? parserMs;

  /// Gönderme -> komut telefona ulaştı (telefon saatiyle).
  int? toplamGecikmeMs;
  final List<String> olaylar = [];
  String? sebep;

  /// LLM'in / hızlı yolun ürettiği JSON (ekranda aynen gösterilir).
  String get komutJson => const JsonEncoder.withIndent('  ').convert({'adimlar': adimlar});
}

/// Konuşma nerede yazıya çevrilir?
enum SttModu {
  /// Yer istasyonunda STT varsa orada (daha doğru), yoksa telefonda.
  otomatik,

  /// Telefonun kendi tanıyıcısı (Faz 7); sunucuya sadece metin gider.
  telefon,

  /// Ham ses yer istasyonuna akar, orada yazıya çevrilir (Faz 8-9).
  yer,
}
