import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ayarlar/ayarlar.dart';
import '../baglanti/telsiz_istemcisi.dart';
import '../geri_bildirim/geri_bildirimci.dart';
import '../protokol/baglanti_adresi.dart';
import '../protokol/mesajlar.dart';
import '../ses/cihaz_tanima.dart';
import '../ses/halka_tampon.dart';
import '../ses/mikrofon.dart';
import '../ses/pcm_parcalayici.dart';
import '../ses/seviye.dart';
import 'komut_aciklama.dart';
import 'modeller.dart';

/// Uygulamanın beyni (Faz 4: bağlantı; 5: kartlar; 6: ACİL DUR; 7: telefon STT;
/// Faz 8: ham ses akışı ve iki STT modu; Faz 10: telemetri ve sesli yanıt).
///
/// Yer STT modu  : tuşa basınca ptt_basla + ön kayıt (300 ms) + canlı 20 ms
///                 parçalar; bırakınca +son kayıt (150 ms) ve ptt_bitti.
/// Telefon modu  : tuşa basınca cihaz tanıyıcısı dinler; bırakınca metin gider.
/// Her iki modda da metni ANLAMA işi (normalize, hızlı yol, LLM, güvenlik)
/// yer istasyonundaki command_parser + mission_executor'da kalır.
class TelsizKontrolcusu extends ChangeNotifier {
  TelsizKontrolcusu({
    required this.baglanti,
    required this.mikrofon,
    required this.tanima,
    required this.geriBildirim,
    this.ayarlar = const Ayarlar(),
    this.enKisaBasma = const Duration(milliseconds: 250),
    this.enFazlaKart = 50,
  }) {
    baglanti.durum.addListener(_baglantiDegisti);
    _abonelik = baglanti.mesajlar.listen(_mesaj);
  }

  final TelsizBaglantisi baglanti;
  final SesKaynagi mikrofon;
  final CihazTanima tanima;
  final GeriBildirimci geriBildirim;
  final Duration enKisaBasma;
  final int enFazlaKart;

  /// Değiştirmek için ayarlariGuncelle() kullan (mikrofon ve TTS de güncellenir).
  Ayarlar ayarlar;
  late final StreamSubscription<Map<String, dynamic>> _abonelik;

  final List<KonusmaKarti> kartlar = [];
  String rol = 'operator';
  bool yerSttVar = false;
  String? sttMotoru;
  double enUzunKonusmaS = 15;
  PttDurumu ptt = PttDurumu.bos;
  double seviye = 0;
  String? kismiMetin;

  /// Son PX4 telemetrisi (köprü 2 Hz gönderir).
  Telemetri telemetri = const Telemetri();

  /// Üst şeritte gösterilen son önemli uyarı (telsiz koptu, acil dur, hata...).
  String? bildirim;

  final HalkaTampon _onKayit = HalkaTampon(msToBayt(300));
  final PcmParcalayici _parcalayici = PcmParcalayici();
  final Map<int, DateTime> _birakmaZamani = {};
  KonusmaKarti? _aktif;
  DateTime? _basmaZamani;
  bool _akitiyor = false;
  int _sira = 0;
  int _sonId = DateTime.now().millisecondsSinceEpoch % 1000000000;
  bool _tanimaHazir = false;

  BaglantiDurumu get baglantiDurumu => baglanti.durum.value;
  bool get bagli => baglantiDurumu == BaglantiDurumu.bagli;
  bool get komutVerebilir => bagli && rol == 'operator';

  /// Bu oturumda en az bir kez bağlanıldı mı? (Kopunca bağlan ekranına atmamak için.)
  bool bagliOldu = false;

  /// Otomatik modda sunucuda STT varsa yer, yoksa telefon.
  SttModu get etkinMod => switch (ayarlar.sttModu) {
    SttModu.otomatik => yerSttVar ? SttModu.yer : SttModu.telefon,
    final m => m,
  };

  // ------------------------------------------------------------------ bağlantı
  Future<void> baglan(BaglantiAdresi adres) => baglanti.baglan(adres, izleyici: ayarlar.izleyici);

  Future<void> kopar() async {
    bagliOldu = false;
    await _mikrofonKapat();
    await baglanti.kopar();
  }

  void _baglantiDegisti() {
    if (bagli) bagliOldu = true;
    if (!bagli) {
      if (ptt != PttDurumu.bos) unawaited(pttIptal());
      unawaited(_mikrofonKapat());
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ ayarlar
  Future<void> ayarlariGuncelle(Ayarlar yeni) async {
    ayarlar = yeni;
    if (geriBildirim case final CihazGeriBildirimci g) {
      g
        ..sesAcik = yeni.sesliYanit
        ..titresimAcik = yeni.titresim;
    }
    await _onKayitDurumunuUygula();
    notifyListeners();
  }

  /// Ön kayıt için mikrofon yer STT modunda, bağlıyken sürekli açık kalır
  /// (veri telefondan çıkmaz; yalnızca son 300 ms halka tamponda tutulur).
  Future<void> _onKayitDurumunuUygula() async {
    final gerekli = bagli && rol == 'operator' && etkinMod == SttModu.yer && ayarlar.onKayit;
    if (gerekli && !mikrofon.acik) {
      await _mikrofonAc();
    } else if (!gerekli && mikrofon.acik && ptt == PttDurumu.bos) {
      await _mikrofonKapat();
    }
  }

  Future<bool> _mikrofonAc() async {
    if (mikrofon.acik) return true;
    if (!await mikrofon.izinIste()) {
      _bildir('mikrofon izni verilmedi');
      return false;
    }
    await mikrofon.ac(_mikrofonVerisi, gurultuBastirma: ayarlar.gurultuBastirma);
    return true;
  }

  Future<void> _mikrofonKapat() async {
    _akitiyor = false;
    _onKayit.temizle();
    if (mikrofon.acik) await mikrofon.kapat();
  }

  // ------------------------------------------------------------------ bas-konuş
  Future<void> pttBasla() async {
    if (!komutVerebilir || ptt != PttDurumu.bos) return;
    geriBildirim.titresim(Titresim.basla);
    unawaited(geriBildirim.sustur()); // telsizde konuşan araya girer: TTS sussun
    final kart = _yeniKart('ses');
    _aktif = kart;
    _basmaZamani = DateTime.now();
    ptt = PttDurumu.dinliyor;
    kismiMetin = null;
    notifyListeners();

    if (etkinMod == SttModu.yer) {
      _sira = 0;
      _parcalayici.sifirla();
      baglanti.gonder('ptt_basla', {'id': kart.id});
      final once = _onKayit.al();
      _onKayit.temizle();
      _akitiyor = true;
      for (final p in _parcalayici.ekle(once)) {
        _sesYolla(kart.id, p);
      }
      if (!await _mikrofonAc()) await pttIptal();
    } else {
      try {
        if (!_tanimaHazir) _tanimaHazir = await tanima.hazirla();
        if (!_tanimaHazir) throw StateError('konuşma tanıma bu cihazda kullanılamıyor');
        await tanima.basla(
          dil: ayarlar.dil,
          cevrimdisi: ayarlar.cevrimdisiTanima,
          kismi: (m) {
            kismiMetin = m;
            notifyListeners();
          },
        );
      } catch (e) {
        _kartiBitir(kart, KartDurumu.anlasilmadi, 'telefon tanıyıcısı başlamadı: $e');
        _aktif = null;
        ptt = PttDurumu.bos;
        notifyListeners();
      }
    }
  }

  Future<void> pttBirak() async {
    final kart = _aktif;
    if (ptt != PttDurumu.dinliyor || kart == null) return;
    final basma = _basmaZamani ?? DateTime.now();
    if (DateTime.now().difference(basma) < enKisaBasma) {
      await pttIptal(); // cebe sürtünme, yanlış dokunuş
      return;
    }
    geriBildirim.titresim(Titresim.birak);
    _birakmaZamani[kart.id] = DateTime.now();
    ptt = PttDurumu.isleniyor;
    notifyListeners();

    if (etkinMod == SttModu.yer) {
      // Son hece kesilmesin: tuştan sonra biraz daha kayıt.
      await Future<void>.delayed(Duration(milliseconds: ayarlar.sonKayitMs));
      _akitiyor = false;
      final kalan = _parcalayici.bosalt();
      if (kalan != null) _sesYolla(kart.id, kalan);
      baglanti.gonder('ptt_bitti', {'id': kart.id, 'parca_sayisi': _sira});
      kart.durum = KartDurumu.isleniyor;
      if (!ayarlar.onKayit) await _mikrofonKapat();
    } else {
      try {
        final sonuc = await tanima.bitir();
        if (sonuc == null) {
          _kartiBitir(kart, KartDurumu.anlasilmadi, 'ses duyulmadı');
        } else {
          kart
            ..duyulan = sonuc.metin
            ..sttKaynagi = 'telefon_stt'
            ..durum = KartDurumu.isleniyor;
          baglanti.gonder('metin', {
            'id': kart.id,
            'metin': sonuc.metin,
            'kaynak': 'telefon_stt',
            'guven': sonuc.guven,
          });
        }
      } catch (e) {
        _kartiBitir(kart, KartDurumu.anlasilmadi, 'tanıma hatası: $e');
      }
    }
    _aktif = null;
    ptt = PttDurumu.bos;
    seviye = 0;
    kismiMetin = null;
    notifyListeners();
  }

  Future<void> pttIptal() async {
    final kart = _aktif;
    _aktif = null;
    if (kart != null) {
      if (etkinMod == SttModu.yer) {
        _akitiyor = false;
        _parcalayici.sifirla();
        if (bagli) baglanti.gonder('ptt_iptal', {'id': kart.id});
        if (!ayarlar.onKayit) await _mikrofonKapat();
      } else {
        await tanima.iptal();
      }
      kartlar.remove(kart);
    }
    ptt = PttDurumu.bos;
    seviye = 0;
    kismiMetin = null;
    notifyListeners();
  }

  void _mikrofonVerisi(Uint8List veri) {
    seviye = sesSeviyesi(veri);
    final kart = _aktif;
    if (_akitiyor && kart != null) {
      for (final p in _parcalayici.ekle(veri)) {
        _sesYolla(kart.id, p);
      }
      if (_sira * 0.02 > enUzunKonusmaS) unawaited(pttBirak()); // en uzun konuşma sınırı
    } else if (ayarlar.onKayit) {
      _onKayit.ekle(veri);
    }
    if (ptt == PttDurumu.dinliyor) notifyListeners();
  }

  void _sesYolla(int id, Uint8List pcm) => baglanti.sesGonder(sesParcasi(id, _sira++, pcm));

  // ------------------------------------------------------------------ yazılı komut, acil
  /// Yazıyla ya da hızlı tuşla komut. Ses gibi command_parser'dan geçer
  /// (normalize, hızlı yol, LLM, güvenlik); telefon komutu kendisi YORUMLAMAZ.
  void metinGonder(String metin, {String giris = 'klavye'}) {
    final temiz = metin.trim();
    if (!komutVerebilir || temiz.isEmpty) return;
    final kart = _yeniKart(giris)
      ..duyulan = temiz
      ..sttKaynagi = giris
      ..durum = KartDurumu.isleniyor;
    _birakmaZamani[kart.id] = DateTime.now();
    baglanti.gonder('metin', {'id': kart.id, 'metin': temiz, 'kaynak': giris});
    notifyListeners();
  }

  /// ACİL DUR: STT ve LLM'e uğramadan /drone/emergency_stop. İzleyici de verebilir.
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
        sttMotoru = m['stt_motoru'] as String?;
        enUzunKonusmaS = (m['en_uzun_konusma_s'] as num?)?.toDouble() ?? 15;
        bildirim = rol == 'izleyici' ? 'izleyici olarak bağlandın (sadece ACİL DUR)' : null;
        unawaited(_onKayitDurumunuUygula());
      case 'isleniyor':
        kart?.durum = KartDurumu.isleniyor;
        if (m['kayip_parca'] case final int n when n > 0) kart?.olaylar.add('$n ses parçası kayıp');
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
        final birakma = id == null ? null : _birakmaZamani.remove(id);
        if (birakma != null) k.toplamGecikmeMs = DateTime.now().difference(birakma).inMilliseconds;
        geriBildirim.titresim(Titresim.kabul);
      case 'anlasilmadi':
        if (kart != null) {
          _kartiBitir(kart, KartDurumu.anlasilmadi, m['sebep'] as String?);
          geriBildirim.titresim(Titresim.red);
          unawaited(geriBildirim.soyle('Anlamadım'));
        }
      case 'geri_bildirim':
        _geriBildirim(kart, m['durum'] as String? ?? '', m['mesaj'] as String? ?? '');
      case 'telemetri':
        telemetri = Telemetri.fromJson(m);
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

  void _geriBildirim(KonusmaKarti? kart, String durum, String mesaj) {
    if (durum == 'acil_dur' || durum == 'telsiz_koptu') {
      bildirim = mesaj;
      geriBildirim.titresim(Titresim.acil);
      unawaited(geriBildirim.soyle(durum == 'acil_dur' ? 'Acil dur' : 'Telsiz bağlantısı koptu'));
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
        unawaited(geriBildirim.soyle(mesaj)); // "20 metre yükseliyorum"
      case 'tamamlandi':
        kart.durum = KartDurumu.tamamlandi;
      case 'reddedildi':
      case 'hata':
        _kartiBitir(kart, KartDurumu.reddedildi, mesaj);
        geriBildirim.titresim(Titresim.red);
        unawaited(geriBildirim.soyle('Reddedildi. $mesaj'));
    }
  }

  // ------------------------------------------------------------------ yardımcılar
  KonusmaKarti _yeniKart(String giris) {
    _sonId = (_sonId + 1) % 4000000000;
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
    _birakmaZamani.remove(kart.id);
  }

  void _bildir(String mesaj) {
    bildirim = mesaj;
    notifyListeners();
  }

  void bildirimiKapat() {
    bildirim = null;
    notifyListeners();
  }

  /// Kart başlığı: komut varsa okunur hali, yoksa duyulan metin.
  static String kartBasligi(KonusmaKarti k) =>
      k.adimlar.isNotEmpty ? adimlarAciklamasi(k.adimlar) : (k.duyulan ?? '…');

  @override
  void dispose() {
    baglanti.durum.removeListener(_baglantiDegisti);
    unawaited(_abonelik.cancel());
    unawaited(_mikrofonKapat());
    super.dispose();
  }
}
