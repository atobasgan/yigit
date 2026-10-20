import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ayarlar/ayarlar.dart';
import '../baglanti/telsiz_istemcisi.dart';
import '../geri_bildirim/geri_bildirimci.dart';
import '../protokol/baglanti_adresi.dart';
import 'komut_aciklama.dart';
import 'modeller.dart';

/// Uygulamanın beyni (Faz 4: bağlantı ve rol; Faz 5: komutlar ve kartlar;
/// Faz 6: ACİL DUR ve güvenlik bildirimleri).
///
/// Ekranlar bu nesneyi dinler (ChangeNotifier). Kontrolcü bağlantıdan gelen
/// mesajları işler, durumu günceller ve notifyListeners() ile ekranlara
/// "yeniden çiz" der. Ekranlar mantık içermez; sadece kontrolcüyü gösterir.
class TelsizKontrolcusu extends ChangeNotifier {
  TelsizKontrolcusu({
    required this.baglanti,
    required this.geriBildirim,
    this.ayarlar = const Ayarlar(),
    this.enFazlaKart = 50,
  }) {
    baglanti.durum.addListener(_baglantiDegisti);
    _abonelik = baglanti.mesajlar.listen(_mesaj);
  }

  /// Arayüz (interface): gerçekte TelsizIstemcisi, testlerde SahteBaglanti.
  final TelsizBaglantisi baglanti;
  final GeriBildirimci geriBildirim;

  final int enFazlaKart;

  /// Değiştirmek için ayarlariGuncelle() kullan.
  Ayarlar ayarlar;

  /// Konuşma kartları, en yenisi başta.
  final List<KonusmaKarti> kartlar = [];
  final Map<int, DateTime> _gondermeZamani = {};
  int _sonId = DateTime.now().millisecondsSinceEpoch % 1000000000;
  late final StreamSubscription<Map<String, dynamic>> _abonelik;

  String rol = 'operator';
  bool yerSttVar = false;

  /// Üst şeritte gösterilen son önemli uyarı.
  String? bildirim;

  BaglantiDurumu get baglantiDurumu => baglanti.durum.value;
  bool get bagli => baglantiDurumu == BaglantiDurumu.bagli;
  bool get komutVerebilir => bagli && rol == 'operator';

  /// Bu oturumda en az bir kez bağlanıldı mı? (Kopunca bağlan ekranına atmamak için.)
  bool bagliOldu = false;

  Future<void> baglan(BaglantiAdresi adres) => baglanti.baglan(adres, izleyici: ayarlar.izleyici);

  Future<void> kopar() async {
    bagliOldu = false;
    await baglanti.kopar();
  }

  Future<void> ayarlariGuncelle(Ayarlar yeni) async {
    ayarlar = yeni;
    notifyListeners();
  }

  void _baglantiDegisti() {
    if (bagli) bagliOldu = true;
    notifyListeners();
  }

  // ------------------------------------------------------------------ komut gönder
  /// Yazıyla ya da hızlı tuşla komut. Telefon komutu kendisi YORUMLAMAZ:
  /// metin yer istasyonundaki command_parser'dan geçer (normalize, hızlı yol,
  /// LLM, güvenlik). Telefon yalnızca sonucu gösterir.
  void metinGonder(String metin, {String giris = 'klavye'}) {
    final temiz = metin.trim();
    if (!komutVerebilir || temiz.isEmpty) return;
    final kart = _yeniKart(giris)
      ..duyulan = temiz
      ..sttKaynagi = giris
      ..durum = KartDurumu.isleniyor;
    _gondermeZamani[kart.id] = DateTime.now();
    baglanti.gonder('metin', {'id': kart.id, 'metin': temiz, 'kaynak': giris});
    notifyListeners();
  }

  /// ACİL DUR: STT ve LLM'e uğramadan /drone/emergency_stop. İzleyici de verebilir.
  /// Bu, telefonun "yorum yapmadan" verdiği tek karardır.
  void acilDur() {
    if (!bagli) {
      _bildir('bağlantı yok: ACİL DUR gönderilemedi!');
      return;
    }
    baglanti.gonder('acil_dur');
    geriBildirim.titresim(Titresim.acil);
    _bildir('ACİL DUR gönderildi');
  }

  // ------------------------------------------------------------------ gelen mesajlar
  void _mesaj(Map<String, dynamic> m) {
    final id = m['id'] as int?;
    final kart = id == null ? null : _kartBul(id);
    switch (m['tip']) {
      case 'hos_geldin':
        rol = m['rol'] as String? ?? 'izleyici';
        yerSttVar = m['yer_stt'] == true;
        bildirim = rol == 'izleyici' ? 'izleyici olarak bağlandın (sadece ACİL DUR)' : null;
      case 'duyuldu':
        final k = kart ?? _uzakKart(id);
        k
          ..duyulan = m['metin'] as String?
          ..sttKaynagi = m['kaynak'] as String?
          ..sttMs = m['stt_ms'] as int?;
        // Mesajlar sırasız gelebilir: komut zaten geldiyse durumu geri çekme.
        if (k.durum case KartDurumu.dinleniyor || KartDurumu.isleniyor) k.durum = KartDurumu.duyuldu;
      case 'komut':
        final k = kart ?? _uzakKart(id);
        k
          ..adimlar = [
            for (final a in (m['adimlar'] as List? ?? const [])) Map<String, dynamic>.from(a as Map),
          ]
          ..komutKaynagi = m['kaynak'] as String?
          ..normalize = m['metin'] as String?
          ..kuyrugaEklendi = m['kuyruga_ekle'] == true
          ..parserMs = (m['parser_ms'] as num?)?.toDouble()
          ..durum = KartDurumu.komut;
        final gonderme = id == null ? null : _gondermeZamani.remove(id);
        if (gonderme != null) k.toplamGecikmeMs = DateTime.now().difference(gonderme).inMilliseconds;
        geriBildirim.titresim(Titresim.kabul);
      case 'anlasilmadi':
        if (kart != null) {
          _kartiBitir(kart, KartDurumu.anlasilmadi, m['sebep'] as String?);
          geriBildirim.titresim(Titresim.red);
        }
      case 'geri_bildirim':
        _geriBildirim(kart, m['durum'] as String? ?? '', m['mesaj'] as String? ?? '');
      case 'hata':
        final mesaj = m['mesaj'] as String? ?? 'bilinmeyen hata';
        if (kart != null) {
          _kartiBitir(kart, KartDurumu.anlasilmadi, mesaj);
        } else {
          bildirim = mesaj;
        }
      default:
        return;
    }
    notifyListeners();
  }

  /// Yürütücünün geri bildirimleri kartın durumunu ilerletir.
  void _geriBildirim(KonusmaKarti? kart, String durum, String mesaj) {
    // Herkesi ilgilendiren güvenlik olayları: üst şeritte göster.
    if (durum == 'acil_dur' || durum == 'telsiz_koptu') {
      bildirim = mesaj;
      geriBildirim.titresim(Titresim.acil);
      return;
    }
    if (kart == null) {
      if (durum == 'reddedildi' || durum == 'hata') bildirim = mesaj;
      return;
    }
    kart.olaylar.add(mesaj);
    switch (durum) {
      case 'yurutuyor':
        kart.durum = KartDurumu.yurutuyor;
      case 'tamamlandi':
        kart.durum = KartDurumu.tamamlandi;
      case 'reddedildi':
      case 'hata':
        _kartiBitir(kart, KartDurumu.reddedildi, mesaj);
        geriBildirim.titresim(Titresim.red);
    }
  }

  // ------------------------------------------------------------------ yardımcılar
  KonusmaKarti _yeniKart(String giris) {
    _sonId = (_sonId + 1) % 4000000000; // protokolde id uint32
    final kart = KonusmaKarti(id: _sonId, giris: giris);
    kartlar.insert(0, kart);
    if (kartlar.length > enFazlaKart) kartlar.removeLast();
    return kart;
  }

  /// Başka bir operatörün (izleyiciyken) ya da id'siz gelen komut için kart.
  KonusmaKarti _uzakKart(int? id) {
    final kart = KonusmaKarti(id: id ?? -DateTime.now().millisecondsSinceEpoch, giris: 'uzak');
    kartlar.insert(0, kart);
    if (kartlar.length > enFazlaKart) kartlar.removeLast();
    return kart;
  }

  KonusmaKarti? _kartBul(int id) {
    for (final k in kartlar) {
      if (k.id == id) return k;
    }
    return null;
  }

  void _kartiBitir(KonusmaKarti kart, KartDurumu durum, String? sebep) {
    kart
      ..durum = durum
      ..sebep = sebep;
    _gondermeZamani.remove(kart.id);
  }

  /// Kart başlığı: komut varsa okunur hali, yoksa duyulan metin.
  static String kartBasligi(KonusmaKarti k) =>
      k.adimlar.isNotEmpty ? adimlarAciklamasi(k.adimlar) : (k.duyulan ?? '…');

  void _bildir(String mesaj) {
    bildirim = mesaj;
    notifyListeners();
  }

  void bildirimiKapat() {
    bildirim = null;
    notifyListeners();
  }

  @override
  void dispose() {
    baglanti.durum.removeListener(_baglantiDegisti);
    unawaited(_abonelik.cancel());
    super.dispose();
  }
}
