import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/durum/telsiz_kontrolcusu.dart';
import 'package:telsiz/geri_bildirim/geri_bildirimci.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';

import 'sahteler.dart';

void main() {
  test('hos_geldin gelince bağlı ve operatör', () async {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
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
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'izleyici'});
    expect(k.komutVerebilir, isFalse);
    expect(k.bildirim, contains('izleyici'));
  });

  test('bağlantı koparsa ekran kalır, kullanıcı koparırsa bağlan ekranına döner', () async {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator'});
    b.koptu();
    expect(k.bagli, isFalse);
    expect(k.bagliOldu, isTrue);
    await k.kopar();
    expect(k.bagliOldu, isFalse);
  });

  test('sunucu hatası bildirime yazılır', () {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hata', 'kod': 'yetkisiz', 'mesaj': 'token hatalı'});
    expect(k.bildirim, 'token hatalı');
  });

  // ---------------------------------------------------------------- Faz 5
  test('yazılı komut: metin gider, JSON komut kartı doldurur', () {
    final b = SahteBaglanti();
    final k = bagliKontrolcu(b);
    k.metinGonder(' önce 20 metre yüksel sonra kuzeye 50 metre git ');
    final giden = b.giden.single;
    expect(giden['tip'], 'metin');
    expect(giden['metin'], 'önce 20 metre yüksel sonra kuzeye 50 metre git');
    expect(giden['kaynak'], 'klavye');
    final id = giden['id'] as int;
    final kart = k.kartlar.single;
    expect(kart.durum, KartDurumu.isleniyor);

    b.gelsin({'tip': 'duyuldu', 'id': id, 'metin': giden['metin'], 'kaynak': 'klavye'});
    expect(kart.durum, KartDurumu.duyuldu);
    b.gelsin({
      'tip': 'komut',
      'id': id,
      'metin': 'önce 20 m yüksel sonra kuzeye 50 m git',
      'kaynak': 'llm',
      'kuyruga_ekle': false,
      'adimlar': [
        {'komut': 'yuksel', 'metre': 20},
        {'komut': 'git_yon', 'yon': 'kuzey', 'metre': 50},
      ],
      'parser_ms': 812.0,
    });
    expect(kart.durum, KartDurumu.komut);
    expect(kart.komutKaynagi, 'llm');
    expect(kart.normalize, 'önce 20 m yüksel sonra kuzeye 50 m git');
    expect(kart.toplamGecikmeMs, isNotNull);
    expect(kart.komutJson, contains('"yon": "kuzey"'));
    expect(TelsizKontrolcusu.kartBasligi(kart), '20 m yüksel → kuzeye 50 m git');

    b.gelsin({'tip': 'geri_bildirim', 'id': id, 'durum': 'yurutuyor', 'mesaj': '20 metre yükseliyorum'});
    expect(kart.durum, KartDurumu.yurutuyor);
    b.gelsin({'tip': 'geri_bildirim', 'id': id, 'durum': 'tamamlandi', 'mesaj': 'git_yon tamamlandı'});
    expect(kart.durum, KartDurumu.tamamlandi);
    expect(kart.olaylar, ['20 metre yükseliyorum', 'git_yon tamamlandı']);
  });

  test('güvenlik reddi ve anlaşılmayan cümle', () {
    final b = SahteBaglanti();
    final k = bagliKontrolcu(b);
    k.metinGonder('5000 metre yüksel');
    b.gelsin({
      'tip': 'geri_bildirim',
      'id': b.giden.last['id'],
      'durum': 'reddedildi',
      'mesaj': 'hedef irtifa 5010 m, sınır 120 m',
    });
    expect(k.kartlar.first.durum, KartDurumu.reddedildi);
    expect(k.kartlar.first.sebep, contains('120'));

    k.metinGonder('saat kaç');
    b.gelsin({'tip': 'anlasilmadi', 'id': b.giden.last['id'], 'sebep': 'anlamadım: "saat kaç"'});
    expect(k.kartlar.first.durum, KartDurumu.anlasilmadi);
  });

  test('mesajlar sırasız gelirse durum geri çekilmez', () {
    final b = SahteBaglanti();
    final k = bagliKontrolcu(b);
    k.metinGonder('kalk');
    final id = b.giden.last['id'];
    b.gelsin({
      'tip': 'komut',
      'id': id,
      'kaynak': 'hizli_yol',
      'adimlar': [
        {'komut': 'kalk'},
      ],
    });
    b.gelsin({'tip': 'duyuldu', 'id': id, 'metin': 'kalk', 'kaynak': 'klavye'});
    expect(k.kartlar.first.durum, KartDurumu.komut);
  });

  test('izleyici komut gönderemez; başkasının komutu uzak kart olur', () {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'izleyici'});
    k.metinGonder('kalk');
    expect(b.giden, isEmpty);
    b.gelsin({'tip': 'duyuldu', 'id': 77, 'metin': 'kalk', 'kaynak': 'klavye'});
    expect(k.kartlar.single.giris, 'uzak');
  });

  // ---------------------------------------------------------------- Faz 6
  test('izleyici konuşamaz ama ACİL DUR verebilir', () {
    final b = SahteBaglanti();
    final g = SahteGeriBildirim();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: g,
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'izleyici'});
    k.metinGonder('kalk');
    expect(b.giden, isEmpty);
    k.acilDur();
    expect(b.tipler, ['acil_dur']);
    expect(g.titresimler.last, Titresim.acil);
  });

  test('bağlantı yokken ACİL DUR kullanıcıyı uyarır', () {
    final b = SahteBaglanti();
    final k = bagliKontrolcu(b);
    b.koptu();
    k.acilDur();
    expect(b.giden, isEmpty);
    expect(k.bildirim, contains('gönderilemedi'));
  });

  test('telsiz koptu ve acil dur olayları üst şeride gelir', () {
    final b = SahteBaglanti();
    final k = bagliKontrolcu(b);
    b.gelsin({
      'tip': 'geri_bildirim',
      'id': null,
      'durum': 'telsiz_koptu',
      'mesaj': 'operatörden 3 sn sinyal yok; drone yerinde asılı kalıyor',
    });
    expect(k.bildirim, contains('asılı'));
    b.gelsin({
      'tip': 'geri_bildirim',
      'id': null,
      'durum': 'acil_dur',
      'mesaj': 'ACİL DUR (izleyici telefon)',
    });
    expect(k.bildirim, 'ACİL DUR (izleyici telefon)');
  });

  test('ACİL DUR yüzünden iptal edilen LLM sonucu kartta reddedildi görünür', () {
    final b = SahteBaglanti();
    final k = bagliKontrolcu(b);
    k.metinGonder('önce on metre yüksel sonra doğuya otuz metre git');
    b.gelsin({
      'tip': 'geri_bildirim',
      'id': b.giden.last['id'],
      'durum': 'reddedildi',
      'mesaj': 'ACİL DUR geldiği için "..." iptal edildi',
    });
    expect(k.kartlar.first.durum, KartDurumu.reddedildi);
    expect(k.kartlar.first.sebep, contains('ACİL DUR'));
  });

  // ---------------------------------------------------------------- Faz 7
  test('bas-konuş: tanıyıcı dinler, bırakınca METİN gider', () async {
    final b = SahteBaglanti();
    final t = SahteTanima();
    final g = SahteGeriBildirim();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: g,
      tanima: t,
      mikrofon: SahteMikrofon(),
      enKisaBasma: Duration.zero,
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator'});
    await k.pttBasla();
    expect(k.ptt, PttDurumu.dinliyor);
    expect(t.dinliyor, isTrue);
    expect(t.sonDil, 'tr_TR');
    expect(k.kismiMetin, '20 metre', reason: 'ara sonuç ekranda');
    await k.pttBirak();
    final m = b.giden.single;
    expect(m['tip'], 'metin');
    expect(m['metin'], '20 metre yüksel');
    expect(m['kaynak'], 'telefon_stt');
    expect(k.kartlar.single.duyulan, '20 metre yüksel');
    expect(k.kartlar.single.giris, 'ses');
    expect(k.ptt, PttDurumu.bos);
    expect(g.titresimler.take(2), [Titresim.basla, Titresim.birak]);
  });

  test('hiçbir şey duyulmazsa kart anlaşılmadı olur, metin gitmez', () async {
    final b = SahteBaglanti();
    final t = SahteTanima()..sonuc = null;
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: t,
      mikrofon: SahteMikrofon(),
      enKisaBasma: Duration.zero,
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator'});
    await k.pttBasla();
    await k.pttBirak();
    expect(b.giden, isEmpty);
    expect(k.kartlar.single.durum, KartDurumu.anlasilmadi);
  });

  test('çok kısa basış iptal edilir (cebe sürtünme)', () async {
    final b = SahteBaglanti();
    final t = SahteTanima();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: t,
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator'});
    await k.pttBasla();
    await k.pttBirak(); // 250 ms'den kısa
    expect(b.giden, isEmpty);
    expect(k.kartlar, isEmpty);
    expect(t.dinliyor, isFalse);
  });

  test('konuşurken bağlantı koparsa bas-konuş iptal olur', () async {
    final b = SahteBaglanti();
    final k = TelsizKontrolcusu(
      baglanti: b,
      geriBildirim: SahteGeriBildirim(),
      tanima: SahteTanima(),
      mikrofon: SahteMikrofon(),
    );
    b.gelsin({'tip': 'hos_geldin', 'rol': 'operator'});
    await k.pttBasla();
    b.koptu();
    await pumpEventQueue();
    expect(k.ptt, PttDurumu.bos);
    expect(k.kartlar, isEmpty);
  });
}

TelsizKontrolcusu bagliKontrolcu(SahteBaglanti b) {
  final k = TelsizKontrolcusu(
    baglanti: b,
    geriBildirim: SahteGeriBildirim(),
    tanima: SahteTanima(),
    mikrofon: SahteMikrofon(),
  );
  b.gelsin({'tip': 'hos_geldin', 'rol': 'operator', 'yer_stt': false});
  return k;
}
