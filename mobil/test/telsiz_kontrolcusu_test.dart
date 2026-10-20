import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/durum/telsiz_kontrolcusu.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';

import 'sahteler.dart';

void main() {
  test('hos_geldin gelince bağlı ve operatör', () async {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(baglanti: b);
    var bildirimSayisi = 0;
    k.addListener(() => bildirimSayisi++);

    await k.baglan(BaglantiAdresi.coz('10.0.0.2', token: 'T')!);
    expect(k.baglantiDurumu, BaglantiDurumu.baglaniyor);
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator', 'yer_stt': false});
    expect(k.bagli, isTrue);
    expect(k.komutVerebilir, isTrue);
    expect(k.bagliOldu, isTrue);
    expect(bildirimSayisi, greaterThan(0), reason: 'ekranlara haber verildi');
  });

  test('izleyici komut veremez ve bilgilendirilir', () {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(baglanti: b);
    b.gelsin({'tip': 'hos_geldin', 'rol': 'izleyici'});
    expect(k.komutVerebilir, isFalse);
    expect(k.bildirim, contains('izleyici'));
  });

  test('bağlantı koparsa ekran kalır, kullanıcı koparırsa bağlan ekranına döner', () async {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(baglanti: b);
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator'});
    b.koptu();
    expect(k.bagli, isFalse);
    expect(k.bagliOldu, isTrue);
    await k.kopar();
    expect(k.bagliOldu, isFalse);
  });

  test('sunucu hatası bildirime yazılır', () {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(baglanti: b);
    b.gelsin({'tip': 'hata', 'kod': 'yetkisiz', 'mesaj': 'token hatalı'});
    expect(k.bildirim, 'token hatalı');
  });
}
