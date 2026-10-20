import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telsiz/baglanti/telsiz_istemcisi.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/geri_bildirim/geri_bildirimci.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';
import 'package:telsiz/ses/cihaz_tanima.dart';
import 'package:telsiz/ses/mikrofon.dart';

class SahteBaglanti implements TelsizBaglantisi {
  final _durum = ValueNotifier(BaglantiDurumu.kopuk);
  final _mesajlar = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final List<Map<String, Object?>> giden = [];
  final List<Uint8List> ses = [];

  @override
  ValueListenable<BaglantiDurumu> get durum => _durum;
  @override
  Stream<Map<String, dynamic>> get mesajlar => _mesajlar.stream;
  @override
  int? pingMs = 12;
  @override
  String? sonHata;

  /// Sunucudan mesaj gelmiş gibi yap.
  void gelsin(Map<String, dynamic> m) {
    if (m['tip'] == 'hos_geldin') _durum.value = BaglantiDurumu.bagli;
    _mesajlar.add(m);
  }

  void koptu() => _durum.value = BaglantiDurumu.hata;

  List<String> get tipler => [for (final m in giden) m['tip'] as String];

  @override
  Future<void> baglan(BaglantiAdresi adres, {required bool izleyici}) async =>
      _durum.value = BaglantiDurumu.baglaniyor;
  @override
  Future<void> kopar() async => _durum.value = BaglantiDurumu.kopuk;
  @override
  void gonder(String tip, [Map<String, Object?> alanlar = const {}]) => giden.add({'tip': tip, ...alanlar});
  @override
  void sesGonder(Uint8List cerceve) => ses.add(cerceve);
}

class SahteGeriBildirim implements GeriBildirimci {
  final List<Titresim> titresimler = [];

  @override
  void titresim(Titresim tur) => titresimler.add(tur);
}

class SahteTanima implements CihazTanima {
  String? sonuc = '20 metre yüksel';
  bool dinliyor = false;
  String? sonDil;

  @override
  Future<bool> hazirla() async => true;
  @override
  Future<void> basla({required String dil, required bool cevrimdisi, void Function(String)? kismi}) async {
    dinliyor = true;
    sonDil = dil;
    kismi?.call('20 metre');
  }

  @override
  Future<TanimaSonucu?> bitir({Duration bekle = Duration.zero}) async {
    dinliyor = false;
    return sonuc == null ? null : TanimaSonucu(sonuc!, 0.9);
  }

  @override
  Future<void> iptal() async => dinliyor = false;
}

class SahteMikrofon implements SesKaynagi {
  void Function(Uint8List)? _veri;
  bool izin = true;
  int acilma = 0;

  @override
  bool get acik => _veri != null;
  @override
  Future<bool> izinIste() async => izin;
  @override
  Future<void> ac(void Function(Uint8List veri) veri, {bool gurultuBastirma = false}) async {
    _veri = veri;
    acilma++;
  }

  @override
  Future<void> kapat() async => _veri = null;

  /// [ms] kadar ses besle; her bayt [deger].
  void besle(int ms, {int deger = 1}) {
    final n = 16000 * 2 * ms ~/ 1000;
    _veri?.call(Uint8List(n)..fillRange(0, n, deger));
  }
}
