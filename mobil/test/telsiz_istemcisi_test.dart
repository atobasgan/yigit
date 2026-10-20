import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:telsiz/baglanti/telsiz_istemcisi.dart';
import 'package:telsiz/durum/modeller.dart';
import 'package:telsiz/protokol/baglanti_adresi.dart';

/// Test içinde gerçek bir WebSocket sunucusu (dart:io).
class TestSunucusu {
  late HttpServer _http;
  final List<Object> gelen = [];
  final List<WebSocket> baglantilar = [];
  bool cevapVer = true;

  int get port => _http.port;

  Future<void> baslat() async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _http.listen((istek) async {
      final ws = await WebSocketTransformer.upgrade(istek);
      baglantilar.add(ws);
      ws.listen((veri) {
        gelen.add(veri);
        if (!cevapVer || veri is! String) return;
        final m = jsonDecode(veri) as Map<String, dynamic>;
        if (m['tip'] == 'merhaba') {
          ws.add(jsonEncode(m['token'] == 'T'
              ? {'tip': 'hos_geldin', 'rol': m['rol'], 'yer_stt': false}
              : {'tip': 'hata', 'kod': 'yetkisiz', 'mesaj': 'token hatalı'}));
        } else if (m['tip'] == 'ping') {
          ws.add(jsonEncode({'tip': 'pong', 't': m['t']}));
        }
      });
    });
  }

  Future<void> kapat() async {
    for (final b in baglantilar) {
      await b.close();
    }
    await _http.close(force: true);
  }
}

Future<void> bekle(bool Function() kosul, {Duration sure = const Duration(seconds: 5)}) async {
  final son = DateTime.now().add(sure);
  while (!kosul()) {
    if (DateTime.now().isAfter(son)) throw TimeoutException('koşul sağlanmadı');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late TestSunucusu s;
  setUp(() async {
    s = TestSunucusu();
    await s.baslat();
  });
  tearDown(() => s.kapat());

  BaglantiAdresi adres(String token) => BaglantiAdresi.coz('127.0.0.1:${s.port}', token: token)!;

  test('merhaba -> hos_geldin -> bağlı, ping ölçülür', () async {
    final i = TelsizIstemcisi(pingAraligi: const Duration(milliseconds: 50), cihazAdi: 'test');
    await i.baglan(adres('T'), izleyici: false);
    await bekle(() => i.durum.value == BaglantiDurumu.bagli);
    final merhaba = jsonDecode(s.gelen.first as String);
    expect(merhaba, {'tip': 'merhaba', 'surum': 1, 'token': 'T', 'rol': 'operator', 'cihaz': 'test'});
    await bekle(() => i.pingMs != null);
    await i.kopar();
    expect(i.durum.value, BaglantiDurumu.kopuk);
  });

  test('yanlış token: tekrar denemez', () async {
    final i = TelsizIstemcisi(pingAraligi: const Duration(milliseconds: 50));
    await i.baglan(adres('X'), izleyici: true);
    await bekle(() => i.sonHata == 'token hatalı');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(s.baglantilar.length, 1);
    await i.kopar();
  });

  test('sunucu susarsa bağlantı ölü sayılır ve yeniden bağlanır', () async {
    final i = TelsizIstemcisi(
        pingAraligi: const Duration(milliseconds: 50), olumSuresi: const Duration(milliseconds: 300));
    await i.baglan(adres('T'), izleyici: false);
    await bekle(() => i.durum.value == BaglantiDurumu.bagli);
    s.cevapVer = false;
    await bekle(() => i.durum.value != BaglantiDurumu.bagli);
    s.cevapVer = true;
    await bekle(() => i.durum.value == BaglantiDurumu.bagli, sure: const Duration(seconds: 6));
    expect(s.baglantilar.length, greaterThanOrEqualTo(2));
    await i.kopar();
  });
}
