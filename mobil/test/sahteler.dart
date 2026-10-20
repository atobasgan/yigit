import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:telsiz/baglanti/telsiz_istemcisi.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';

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
