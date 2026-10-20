import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/ses/halka_tampon.dart';
import 'package:telsiz/ses/pcm_parcalayici.dart';
import 'package:telsiz/ses/seviye.dart';

void main() {
  group('halka tampon (ön kayıt)', () {
    test('son N baytı sırayla tutar, eskisini ezer', () {
      final t = HalkaTampon(4)
        ..ekle(Uint8List.fromList([1, 2, 3]))
        ..ekle(Uint8List.fromList([4, 5]));
      expect(t.al(), [2, 3, 4, 5]);
      t.ekle(Uint8List.fromList([6, 7, 8, 9, 10]));
      expect(t.al(), [7, 8, 9, 10]);
      t.temizle();
      expect(t.al(), isEmpty);
    });
    test('dolmadan', () {
      final t = HalkaTampon(10)..ekle(Uint8List.fromList([1, 2]));
      expect(t.al(), [1, 2]);
    });
  });

  group('PCM parçalayıcı', () {
    test('640 baytlık (20 ms) parçalar + kalan', () {
      final p = PcmParcalayici();
      expect(p.ekle(Uint8List(500)), isEmpty);
      final parcalar = p.ekle(Uint8List(1000)); // 1500 bayt -> 2 parça, 220 kalan
      expect(parcalar.map((e) => e.length), [640, 640]);
      expect(p.bosalt()!.length, 220);
      expect(p.bosalt(), isNull);
    });
    test('tek bayt kalan kırpılır (PCM16 = 2 bayt/örnek)', () {
      final p = PcmParcalayici()..ekle(Uint8List(3));
      expect(p.bosalt()!.length, 2);
    });
  });

  test('ses seviyesi 0..1', () {
    expect(sesSeviyesi(Uint8List(640)), 0);
    final yuksek = Uint8List(640);
    final v = ByteData.sublistView(yuksek);
    for (var i = 0; i < 320; i++) {
      v.setInt16(i * 2, i.isEven ? 30000 : -30000, Endian.little);
    }
    expect(sesSeviyesi(yuksek), greaterThan(0.9));
  });
}
