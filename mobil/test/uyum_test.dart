/// Gerçek Dart istemcisi <-> gerçek Python köprüsü.
/// Çalıştırmak için: ./scripts/uyum_testi.sh  (TELSIZ_UYUM_URL yoksa atlanır)
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/baglanti/telsiz_istemcisi.dart';
import 'package:telsiz/durum/modeller.dart';
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

  test('telefon <-> köprü: giriş, ping, gerçek parser JSON, güvenlik, anlaşılmayan', () async {
    final istemci = TelsizIstemcisi(cihazAdi: 'uyum_testi', pingAraligi: const Duration(milliseconds: 100));
    final k = TelsizKontrolcusu(baglanti: istemci);
    await k.baglan(BaglantiAdresi.coz(url!)!);
    await bekle(() => k.bagli, 'bağlantı');
    expect(k.rol, 'operator');
    await bekle(() => istemci.pingMs != null, 'ping ölçümü');

    // Faz 5: drone reposunun gerçek hızlı yolu JSON üretir, sanal drone yürütür
    k.metinGonder('kalk');
    final kalk = k.kartlar.first;
    await bekle(() => kalk.durum == KartDurumu.tamamlandi, 'kalk tamamlandı');
    expect(kalk.adimlar, [
      {'komut': 'kalk'}
    ]);
    expect(kalk.komutKaynagi, 'hizli_yol');

    k.metinGonder('yirmi metre yüksel');
    final yuksel = k.kartlar.first;
    await bekle(() => yuksel.adimlar.isNotEmpty, 'yüksel');
    expect(yuksel.normalize, '20 m yüksel');
    expect(yuksel.adimlar, [
      {'komut': 'yuksel', 'metre': 20.0}
    ]);

    k.metinGonder('beş yüz metre yüksel');
    final red = k.kartlar.first;
    await bekle(() => red.durum == KartDurumu.reddedildi, 'güvenlik reddi');
    expect(red.sebep, contains('sınır'));

    k.metinGonder('bugün hava nasıl');
    final anlamsiz = k.kartlar.first;
    await bekle(() => anlamsiz.durum == KartDurumu.anlasilmadi, 'anlaşılmadı');
    await k.kopar();
  }, skip: url == null ? 'TELSIZ_UYUM_URL yok (./scripts/uyum_testi.sh)' : false);
}
