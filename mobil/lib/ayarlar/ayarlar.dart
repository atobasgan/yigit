import 'package:shared_preferences/shared_preferences.dart';

import '../durum/modeller.dart';

/// Kullanıcı ayarları (telefonda saklanır). Her fazda yeni ayarlar eklenir.
class Ayarlar {
  const Ayarlar({
    this.sunucuAdresi = '',
    this.token = '',
    this.izleyici = false,
    this.cevrimdisiTanima = false,
    this.dil = 'tr_TR',
    this.sttModu = SttModu.otomatik,
    this.onKayit = true,
    this.sonKayitMs = 150,
    this.gurultuBastirma = false,
  });

  final String sunucuAdresi;
  final String token;

  /// Sadece izle (komut veremez).
  final bool izleyici;

  /// Telefonda tanımada internetsiz (cihaz üstü) tanıma iste.
  final bool cevrimdisiTanima;

  /// Konuşma tanıma dili.
  final String dil;

  final SttModu sttModu;

  /// Yer STT modunda mikrofonu açık tutup tuştan önceki 300 ms'yi de gönder.
  final bool onKayit;

  /// Tuş bırakıldıktan sonra son hece kesilmesin diye kayda devam süresi.
  final int sonKayitMs;
  final bool gurultuBastirma;

  Ayarlar copyWith({
    String? sunucuAdresi,
    String? token,
    bool? izleyici,
    bool? cevrimdisiTanima,
    SttModu? sttModu,
    bool? onKayit,
    int? sonKayitMs,
    bool? gurultuBastirma,
  }) => Ayarlar(
    sunucuAdresi: sunucuAdresi ?? this.sunucuAdresi,
    token: token ?? this.token,
    izleyici: izleyici ?? this.izleyici,
    cevrimdisiTanima: cevrimdisiTanima ?? this.cevrimdisiTanima,
    dil: dil,
    sttModu: sttModu ?? this.sttModu,
    onKayit: onKayit ?? this.onKayit,
    sonKayitMs: sonKayitMs ?? this.sonKayitMs,
    gurultuBastirma: gurultuBastirma ?? this.gurultuBastirma,
  );
}

/// shared_preferences: telefonda anahtar-değer olarak kalıcı saklama
/// (Android'de SharedPreferences, iOS'ta NSUserDefaults).
class AyarDeposu {
  static Future<Ayarlar> yukle() async {
    final p = await SharedPreferences.getInstance();
    return Ayarlar(
      sunucuAdresi: p.getString('sunucuAdresi') ?? '',
      token: p.getString('token') ?? '',
      izleyici: p.getBool('izleyici') ?? false,
      cevrimdisiTanima: p.getBool('cevrimdisiTanima') ?? false,
      sttModu: SttModu.values.asNameMap()[p.getString('sttModu')] ?? SttModu.otomatik,
      onKayit: p.getBool('onKayit') ?? true,
      sonKayitMs: p.getInt('sonKayitMs') ?? 150,
      gurultuBastirma: p.getBool('gurultuBastirma') ?? false,
    );
  }

  static Future<void> kaydet(Ayarlar a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sunucuAdresi', a.sunucuAdresi);
    await p.setString('token', a.token);
    await p.setBool('izleyici', a.izleyici);
    await p.setBool('cevrimdisiTanima', a.cevrimdisiTanima);
    await p.setString('sttModu', a.sttModu.name);
    await p.setBool('onKayit', a.onKayit);
    await p.setInt('sonKayitMs', a.sonKayitMs);
    await p.setBool('gurultuBastirma', a.gurultuBastirma);
  }
}
