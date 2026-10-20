/// Gerçek Dart istemcisi <-> gerçek Python köprüsü.
/// Çalıştırmak için: ./scripts/uyum_testi.sh  (TELSIZ_UYUM_URL yoksa atlanır)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/baglanti/telsiz_istemcisi.dart';
import 'package:telsiz/durum/telsiz_kontrolcusu.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';

Future<void> bekle(bool Function() kosul, [String ne = 'koşul']) async {
  final son = DateTime.now().add(const Duration(seconds: 8));
  while (!kosul()) {
    if (DateTime.now().isAfter(son)) throw TimeoutException('$ne sağlanmadı');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  final url = Platform.environment['TELSIZ_UYUM_URL'];

  test('telefon <-> köprü: giriş, rol, ping', () async {
    final istemci = TelsizIstemcisi(cihazAdi: 'uyum_testi', pingAraligi: const Duration(milliseconds: 100));
    final k = TelsizKontrolcusu(baglanti: istemci);
    await k.baglan(BaglantiAdresi.coz(url!)!);
    await bekle(() => k.bagli, 'bağlantı');
    expect(k.rol, 'operator');
    await bekle(() => istemci.pingMs != null, 'ping ölçümü');
    expect(istemci.pingMs, lessThan(100));
    await k.kopar();
  }, skip: url == null ? 'TELSIZ_UYUM_URL yok (./scripts/uyum_testi.sh)' : false);
}
