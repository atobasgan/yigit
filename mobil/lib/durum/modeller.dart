/// Uygulamanın veri tipleri.
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

/// Faz 10: PX4 telemetrisi (köprüdeki donustur.telemetri_sozlugu ile aynı alanlar).
/// Değişmez (immutable) bir değer nesnesi: her mesajda yenisi oluşturulur.
class Telemetri {
  const Telemetri({
    this.hazir = false,
    this.irtifa,
    this.hiz,
    this.yaw,
    this.batarya,
    this.arm = false,
    this.havada = false,
    this.mod,
    this.enlem,
    this.boylam,
  });

  factory Telemetri.fromJson(Map<String, dynamic> j) {
    // JSON'da 10 da 10.0 da gelebilir: ikisi de num, toDouble() ile tek tipe çevir.
    double? d(String k) => (j[k] as num?)?.toDouble();
    return Telemetri(
      hazir: j['hazir'] == true,
      irtifa: d('irtifa'),
      hiz: d('hiz'),
      yaw: d('yaw'),
      batarya: d('batarya'),
      arm: j['arm'] == true,
      havada: j['havada'] == true,
      mod: j['mod'] as String?,
      enlem: d('enlem'),
      boylam: d('boylam'),
    );
  }

  /// PX4'ten veri geliyor mu? false ise şerit "telemetri bekleniyor" der.
  final bool hazir;
  final double? irtifa, hiz, yaw, batarya, enlem, boylam;
  final bool arm, havada;
  final String? mod;
}

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
