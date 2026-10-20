// Faz 10: telemetri, Türkçe sesli yanıt (TTS) ve ayarlar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telsiz/ayarlar/ayarlar.dart';
import 'package:telsiz/bilesenler/telemetri_seridi.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/durum/telsiz_kontrolcusu.dart';
import 'package:telsiz/ekranlar/ayarlar_ekrani.dart';

import 'sahteler.dart';

({SahteBaglanti b, SahteGeriBildirim g, TelsizKontrolcusu k}) kur() {
  final b = SahteBaglanti();
  final g = SahteGeriBildirim();
  final k = TelsizKontrolcusu(baglanti: b, geriBildirim: g, tanima: SahteTanima(), mikrofon: SahteMikrofon());
  b.gelsin({'tip': 'hos_geldin', 'rol': 'operator', 'yer_stt': false});
  return (b: b, g: g, k: k);
}

void main() {
  test('telemetri mesajı modele dönüşür (int de double da gelebilir)', () {
    final o = kur();
    expect(o.k.telemetri.hazir, isFalse, reason: 'ilk mesaja kadar "bekleniyor"');
    o.b.gelsin({
      'tip': 'telemetri',
      'hazir': true,
      'irtifa': 20,
      'batarya': 0.86,
      'arm': true,
      'havada': true,
      'mod': 'OFFBOARD',
    });
    expect(o.k.telemetri.irtifa, 20.0);
    expect(o.k.telemetri.havada, isTrue);
    expect(o.k.telemetri.mod, 'OFFBOARD');
  });

  test('sesli yanıt: yürütülüyor, reddedildi, anlaşılmadı, telsiz koptu', () async {
    final o = kur();
    o.k.metinGonder('20 metre yüksel');
    final id = o.b.giden.last['id'];
    o.b.gelsin({'tip': 'komut', 'id': id, 'kaynak': 'hizli_yol', 'adimlar': []});
    o.b.gelsin({'tip': 'geri_bildirim', 'id': id, 'durum': 'yurutuyor', 'mesaj': '20 metre yükseliyorum'});
    expect(o.g.soylenen, ['20 metre yükseliyorum']);

    o.k.metinGonder('beş yüz metre yüksel');
    o.b.gelsin({
      'tip': 'geri_bildirim',
      'id': o.b.giden.last['id'],
      'durum': 'reddedildi',
      'mesaj': 'sınır 120 m',
    });
    expect(o.g.soylenen.last, 'Reddedildi. sınır 120 m');

    o.k.metinGonder('bugün hava nasıl');
    o.b.gelsin({'tip': 'anlasilmadi', 'id': o.b.giden.last['id'], 'sebep': 'komut yok'});
    expect(o.g.soylenen.last, 'Anlamadım');

    o.b.gelsin({'tip': 'geri_bildirim', 'id': null, 'durum': 'telsiz_koptu', 'mesaj': '...'});
    expect(o.g.soylenen.last, 'Telsiz bağlantısı koptu');
  });

  test('bas-konuşa basınca konuşan TTS susar', () async {
    final o = kur();
    await o.k.pttBasla();
    expect(o.g.susturma, 1);
    await o.k.pttIptal();
  });

  testWidgets('telemetri şeridi: değerler ve düşük batarya', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TelemetriSeridi(
            telemetri: Telemetri(
              hazir: true,
              irtifa: 20.3,
              batarya: 0.25,
              havada: true,
              arm: true,
              mod: 'OFFBOARD',
            ),
          ),
        ),
      ),
    );
    expect(find.text('20.3 m'), findsOneWidget);
    expect(find.text('%25'), findsOneWidget);
    expect(find.text('HAVADA'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TelemetriSeridi(telemetri: Telemetri())),
      ),
    );
    expect(find.textContaining('telemetri bekleniyor'), findsOneWidget);
  });

  testWidgets('ayarlar ekranı: değişiklik kontrolcüye ve depoya gider', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final o = kur();
    await tester.pumpWidget(MaterialApp(home: AyarlarEkrani(kontrolcu: o.k)));
    await tester.tap(find.text('Telefonda tanı'));
    await tester.pumpAndSettle();
    expect(o.k.ayarlar.sttModu, SttModu.telefon);

    await tester.scrollUntilVisible(find.text('Sesli yanıt (Türkçe TTS)'), 200);
    await tester.tap(find.text('Sesli yanıt (Türkçe TTS)'));
    await tester.pumpAndSettle();
    expect(o.k.ayarlar.sesliYanit, isFalse);
    expect((await AyarDeposu.yukle()).sesliYanit, isFalse, reason: 'telefonda saklandı');
  });
}
