import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/durum/komut_aciklama.dart';

void main() {
  test('LLM şemasındaki adımlar okunur Türkçeye çevrilir', () {
    expect(adimAciklamasi({'komut': 'yuksel', 'metre': 20}), '20 m yüksel');
    expect(adimAciklamasi({'komut': 'git_yon', 'yon': 'kuzey', 'metre': 50}), 'kuzeye 50 m git');
    expect(adimAciklamasi({'komut': 'don', 'yon': 'sag', 'derece': 90}), 'sağa 90° dön');
    expect(adimAciklamasi({'komut': 'kalk', 'irtifa_m': 10}), "10 m'ye kalk");
    expect(adimAciklamasi({'komut': 'kalk'}), 'kalk');
    expect(adimAciklamasi({'komut': 'alcal', 'metre': 1.5}), '1.5 m alçal');
    expect(adimAciklamasi({'komut': 'bekle', 'saniye': 5}), '5 sn bekle');
    expect(
      adimlarAciklamasi([
        {'komut': 'yuksel', 'metre': 20},
        {'komut': 'eve_don'},
      ]),
      '20 m yüksel → eve dön',
    );
  });

  test('komut kaynağı rozeti', () {
    expect(kaynakEtiketi('hizli_yol'), 'HIZLI YOL');
    expect(kaynakEtiketi('llm'), 'LLM');
    expect(kaynakEtiketi('acil'), 'ACİL');
    expect(kaynakEtiketi(null), '?');
  });
}
