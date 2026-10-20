import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telsiz/app.dart';
import 'package:telsiz/durum/telsiz_kontrolcusu.dart';

import 'sahteler.dart';

void main() {
  testWidgets('bağlan ekranı -> hos_geldin -> telsiz ekranı', (tester) async {
    SharedPreferences.setMockInitialValues({}); // testte gerçek depolama yok
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      enKisaBasma: Duration.zero,
    );
    await tester.pumpWidget(TelsizUygulamasi(kontrolcu: k));
    expect(find.text('Bağlan'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '10.0.0.2:8765');
    await tester.enterText(find.byType(TextField).last, 'T');
    await tester.tap(find.text('Bağlan'));
    await tester.pump();
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator', 'yer_stt': false});
    await tester.pump();

    expect(find.text('OPERATÖR'), findsOneWidget);
    expect(find.text('12 ms'), findsOneWidget, reason: 'ping göstergesi');
    expect(find.text('BAS KONUŞ'), findsOneWidget);

    // Faz 5: hızlı tuş -> metin gider; sunucudan komut gelince kart + JSON
    await tester.tap(find.text('eve dön'));
    expect(b.giden.last, containsPair('metin', 'eve dön'));
    b.gelsin({
      'tip': 'komut',
      'id': b.giden.last['id'],
      'kaynak': 'hizli_yol',
      'metin': 'eve dön',
      'adimlar': [
        {'komut': 'eve_don'},
      ],
    });
    await tester.pump();
    expect(find.text('HIZLI YOL'), findsOneWidget);
    expect(find.textContaining('"komut": "eve_don"'), findsOneWidget);

    // Faz 6: ACİL DUR yer istasyonuna gider
    await tester.tap(find.text('ACİL DUR'));
    expect(b.giden.last['tip'], 'acil_dur');

    // Faz 7: bas-konuş -> telefonun tanıyıcısı -> metin
    final parmak = await tester.startGesture(tester.getCenter(find.text('BAS KONUŞ')));
    await tester.pump();
    expect(find.text('KONUŞ'), findsOneWidget);
    expect(find.text('"20 metre"'), findsOneWidget, reason: 'ara sonuç canlı görünür');
    await parmak.up();
    await tester.pumpAndSettle();
    expect(b.giden.last, containsPair('kaynak', 'telefon_stt'));
    expect(b.giden.last, containsPair('metin', '20 metre yüksel'));
  });
}
