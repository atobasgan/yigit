import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ayarlar/ayarlar.dart';
import '../baglanti/telsiz_istemcisi.dart';
import '../protokol/baglanti_adresi.dart';
import 'modeller.dart';

/// Uygulamanın beyni (Faz 4: bağlantı ve rol).
///
/// Ekranlar bu nesneyi dinler (ChangeNotifier). Kontrolcü bağlantıdan gelen
/// mesajları işler, durumu günceller ve notifyListeners() ile ekranlara
/// "yeniden çiz" der. Ekranlar mantık içermez; sadece kontrolcüyü gösterir.
class TelsizKontrolcusu extends ChangeNotifier {
  TelsizKontrolcusu({required this.baglanti, this.ayarlar = const Ayarlar()}) {
    baglanti.durum.addListener(_baglantiDegisti);
    _abonelik = baglanti.mesajlar.listen(_mesaj);
  }

  /// Arayüz (interface): gerçekte TelsizIstemcisi, testlerde SahteBaglanti.
  final TelsizBaglantisi baglanti;

  /// Değiştirmek için ayarlariGuncelle() kullan.
  Ayarlar ayarlar;
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

  void _mesaj(Map<String, dynamic> m) {
    switch (m['tip']) {
      case 'hos_geldin':
        rol = m['rol'] as String? ?? 'izleyici';
        yerSttVar = m['yer_stt'] == true;
        bildirim = rol == 'izleyici' ? 'izleyici olarak bağlandın' : null;
      case 'hata':
        bildirim = m['mesaj'] as String? ?? 'bilinmeyen hata';
      default:
        return; // diğer mesajlar sonraki fazlarda
    }
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
