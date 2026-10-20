import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';
import 'package:telsiz/protokol/mesajlar.dart';

void main() {
  group('ikili ses çerçevesi', () {
    test('ORTAK TEST VEKTÖRÜ (Python tarafında da aynı bayt dizisi)', () {
      // id = 0x01020304, sıra = 7, PCM = [9, 8]
      final c = sesParcasi(0x01020304, 7, Uint8List.fromList([9, 8]));
      expect(c, [4, 3, 2, 1, 7, 0, 0, 0, 9, 8]); // little-endian: en düşük bayt önce
    });
    test('20 ms = 640 bayt; ms -> bayt hep çift sayı', () {
      expect(parcaBayt, 640);
      expect(msToBayt(300), 9600);
      expect(msToBayt(1) % 2, 0);
    });
  });

  group('JSON kontrol mesajları', () {
    test('yaz', () {
      expect(jsonYaz('metin', {'id': 1, 'metin': 'yüksel'}), '{"tip":"metin","id":1,"metin":"yüksel"}');
      expect(jsonYaz('acil_dur'), '{"tip":"acil_dur"}');
    });
    test('çöz: sadece "tip" alanı olan nesneler kabul', () {
      expect(jsonCoz('{"tip":"pong","t":5}'), {'tip': 'pong', 't': 5});
      expect(jsonCoz('bozuk'), isNull);
      expect(jsonCoz('{"x":1}'), isNull);
      expect(jsonCoz('[1,2]'), isNull);
      expect(jsonCoz(Uint8List(3)), isNull); // ikili çerçeve JSON değildir
    });
  });

  group('bağlantı adresi (QR / elle)', () {
    test('köprünün QR adresi', () {
      final a = BaglantiAdresi.coz('ws://192.168.1.5:8765/telsiz?token=ABC')!;
      expect(a.uri.toString(), 'ws://192.168.1.5:8765/telsiz');
      expect(a.token, 'ABC');
      expect(a.tamMetin, 'ws://192.168.1.5:8765/telsiz?token=ABC');
    });
    test('kısa yazımlar ve ayrı token', () {
      expect(BaglantiAdresi.coz('10.0.0.2')!.uri.toString(), 'ws://10.0.0.2:8765/telsiz');
      expect(BaglantiAdresi.coz('10.0.0.2:9000', token: ' T ')!.token, 'T');
      expect(BaglantiAdresi.coz('ws://h:1/telsiz?token=A', token: 'B')!.token, 'B');
    });
    test('geçersiz', () {
      expect(BaglantiAdresi.coz(''), isNull);
      expect(BaglantiAdresi.coz('http://x'), isNull);
      expect(BaglantiAdresi.coz('ws://'), isNull);
    });
  });
}
