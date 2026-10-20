import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/ayarlar/ayarlar.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/durum/telsiz_kontrolcusu.dart';
import 'package:telsiz/geri_bildirim/geri_bildirimci.dart';

import 'sahteler.dart';

typedef Ortam = ({TelsizKontrolcusu k, SahteBaglanti b, SahteMikrofon m, SahteGeriBildirim g});

Ortam kur({bool yerStt = true, Ayarlar ayarlar = const Ayarlar(sonKayitMs: 0)}) {
  final b = SahteBaglanti();
  final m = SahteMikrofon();
  final g = SahteGeriBildirim();
  final k = TelsizKontrolcusu(
    baglanti: b,
    mikrofon: m,
    tanima: SahteTanima(),
    geriBildirim: g,
    ayarlar: ayarlar,
    enKisaBasma: Duration.zero,
  );
  b.gelsin({'tip': 'hos_geldin', 'rol': 'operator', 'yer_stt': yerStt, 'stt_motoru': 'sahte'});
  return (k: k, b: b, m: m, g: g);
}

/// İkili çerçeveyi çöz: [id][sıra][PCM]
({int id, int sira, int uzunluk, int ilkBayt}) coz(Uint8List c) {
  final v = ByteData.sublistView(c);
  return (
    id: v.getUint32(0, Endian.little),
    sira: v.getUint32(4, Endian.little),
    uzunluk: c.length - 8,
    ilkBayt: c[8],
  );
}

void main() {
  test('otomatik mod: sunucuda STT varsa yer, yoksa telefon', () async {
    expect(kur(yerStt: true).k.etkinMod, SttModu.yer);
    expect(kur(yerStt: false).k.etkinMod, SttModu.telefon);
    expect(kur(yerStt: true, ayarlar: const Ayarlar(sttModu: SttModu.telefon)).k.etkinMod, SttModu.telefon);
  });

  test('ön kayıt + canlı ses + ptt_bitti (bayt bayt)', () async {
    final o = kur();
    await pumpEventQueue();
    expect(o.m.acik, isTrue, reason: 'ön kayıt için mikrofon açık');
    o.m.besle(1000, deger: 7); // tuştan ÖNCE 1 sn: sadece son 300 ms tutulmalı
    expect(o.b.ses, isEmpty, reason: 'tuşa basılmadan ses telefondan ÇIKMAZ');

    await o.k.pttBasla();
    expect(o.b.tipler, ['ptt_basla']);
    final id = o.b.giden.first['id'] as int;
    o.m.besle(1000, deger: 9); // tuşa basılıyken 1 sn
    await o.k.pttBirak();

    final parcalar = o.b.ses.map(coz).toList();
    expect(parcalar.every((p) => p.id == id), isTrue);
    expect(
      [for (final p in parcalar) p.sira],
      List.generate(parcalar.length, (i) => i),
      reason: 'sıra 0,1,2...',
    );
    final onKayit = parcalar.where((p) => p.ilkBayt == 7).fold(0, (s, p) => s + p.uzunluk);
    expect(onKayit, 9600, reason: '300 ms x 16000 Hz x 2 bayt');
    expect(parcalar.fold(0, (s, p) => s + p.uzunluk), 9600 + 32000);
    expect(parcalar.where((p) => p.uzunluk != 640), isEmpty, reason: 'hepsi 20 ms');
    expect(o.b.giden.last, {'tip': 'ptt_bitti', 'id': id, 'parca_sayisi': parcalar.length});
    expect(o.k.kartlar.single.durum, KartDurumu.isleniyor);
    expect(o.g.titresimler.take(2), [Titresim.basla, Titresim.birak]);
  });

  test('ön kayıt kapalı: mikrofon tuşla açılır, bırakınca kapanır', () async {
    final o = kur(ayarlar: const Ayarlar(sonKayitMs: 0, onKayit: false));
    await pumpEventQueue();
    expect(o.m.acik, isFalse);
    await o.k.pttBasla();
    expect(o.m.acik, isTrue);
    o.m.besle(500);
    await o.k.pttBirak();
    expect(o.m.acik, isFalse);
    expect(o.b.tipler.last, 'ptt_bitti');
  });

  test('mikrofon izni yoksa kullanıcı uyarılır', () async {
    final b = SahteBaglanti();
    final m = SahteMikrofon()..izin = false;
    final k = TelsizKontrolcusu(
      baglanti: b,
      mikrofon: m,
      tanima: SahteTanima(),
      geriBildirim: SahteGeriBildirim(),
      ayarlar: const Ayarlar(onKayit: false),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator', 'yer_stt': true});
    await k.pttBasla();
    expect(k.bildirim, contains('izni'));
    expect(k.ptt, PttDurumu.bos);
  });

  test('sunucu "isleniyor" ve "duyuldu" ile kartı ilerletir', () async {
    final o = kur();
    await o.k.pttBasla();
    o.m.besle(500);
    await o.k.pttBirak();
    final id = o.b.giden.first['id'];
    o.b.gelsin({'tip': 'isleniyor', 'id': id, 'sure_ms': 500, 'kayip_parca': 2});
    expect(o.k.kartlar.single.olaylar, ['2 ses parçası kayıp']);
    o.b.gelsin({'tip': 'duyuldu', 'id': id, 'metin': 'Kalk.', 'kaynak': 'yer_stt', 'stt_ms': 1344});
    expect(o.k.kartlar.single.sttMs, 1344);
    expect(o.k.kartlar.single.sttKaynagi, 'yer_stt');
  });

  test('bağlantı koparsa mikrofon kapanır', () async {
    final o = kur();
    await pumpEventQueue();
    expect(o.m.acik, isTrue);
    o.b.koptu();
    await pumpEventQueue();
    expect(o.m.acik, isFalse);
  });
}
