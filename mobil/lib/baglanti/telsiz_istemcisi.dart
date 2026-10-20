import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../durum/modeller.dart';
import '../protokol/baglanti_adresi.dart';
import '../protokol/mesajlar.dart';

/// Yer istasyonuyla bağlantı (testlerde sahtesi kullanılır).
abstract class TelsizBaglantisi {
  ValueListenable<BaglantiDurumu> get durum;
  Stream<Map<String, dynamic>> get mesajlar;

  /// Son ölçülen gidiş-dönüş süresi.
  int? get pingMs;
  String? get sonHata;

  Future<void> baglan(BaglantiAdresi adres, {required bool izleyici});
  Future<void> kopar();
  void gonder(String tip, [Map<String, Object?> alanlar = const {}]);
  void sesGonder(Uint8List cerceve);
}

typedef KanalAcici = WebSocketChannel Function(Uri uri);

/// WebSocket istemcisi:
///  - açılışta "merhaba" (token + rol), "hos_geldin" gelince bağlı sayılır
///  - 1 sn'de bir ping; 4 sn hiç mesaj gelmezse bağlantı ölü sayılır
///  - kopunca 1, 2, 4, 8 sn aralıklarla yeniden bağlanır (kullanıcı koparmadıkça)
class TelsizIstemcisi implements TelsizBaglantisi {
  TelsizIstemcisi({
    KanalAcici? kanalAcici,
    this.pingAraligi = const Duration(seconds: 1),
    this.olumSuresi = const Duration(seconds: 4),
    this.cihazAdi,
  }) : _kanalAcici = kanalAcici ?? WebSocketChannel.connect;

  final KanalAcici _kanalAcici;
  final Duration pingAraligi;
  final Duration olumSuresi;
  final String? cihazAdi;

  final _durum = ValueNotifier(BaglantiDurumu.kopuk);
  final _mesajlar = StreamController<Map<String, dynamic>>.broadcast();
  WebSocketChannel? _kanal;
  StreamSubscription<dynamic>? _abonelik;
  Timer? _pingZamanlayici;
  Timer? _yenidenZamanlayici;
  DateTime _sonGelen = DateTime.now();
  int _deneme = 0;
  bool _istenen = false;
  BaglantiAdresi? _adres;
  bool _izleyici = false;

  @override
  int? pingMs;
  @override
  String? sonHata;

  @override
  ValueListenable<BaglantiDurumu> get durum => _durum;
  @override
  Stream<Map<String, dynamic>> get mesajlar => _mesajlar.stream;

  @override
  Future<void> baglan(BaglantiAdresi adres, {required bool izleyici}) async {
    await _temizle();
    _istenen = true;
    _adres = adres;
    _izleyici = izleyici;
    _deneme = 0;
    await _ac();
  }

  Future<void> _ac() async {
    final adres = _adres;
    if (adres == null || !_istenen) return;
    _durum.value = BaglantiDurumu.baglaniyor;
    try {
      final kanal = _kanalAcici(adres.uri);
      await kanal.ready.timeout(const Duration(seconds: 5));
      _kanal = kanal;
      _sonGelen = DateTime.now();
      _abonelik = kanal.stream.listen(_gelen, onDone: _kapandi, onError: (_) => _kapandi());
      gonder('merhaba', {
        'surum': protokolSurumu,
        'token': adres.token,
        'rol': _izleyici ? 'izleyici' : 'operator',
        'cihaz': cihazAdi ?? _platformAdi(),
      });
      _pingZamanlayici = Timer.periodic(pingAraligi, (_) => _pingAt());
    } catch (e) {
      sonHata = 'bağlanılamadı: $e';
      await _temizle();
      _durum.value = BaglantiDurumu.hata;
      _yenidenPlanla();
    }
  }

  void _gelen(dynamic veri) {
    _sonGelen = DateTime.now();
    final m = jsonCoz(veri);
    if (m == null) return;
    switch (m['tip']) {
      case 'hos_geldin':
        _deneme = 0;
        sonHata = null;
        _durum.value = BaglantiDurumu.bagli;
      case 'pong':
        final t = m['t'];
        if (t is int) pingMs = DateTime.now().millisecondsSinceEpoch - t;
      case 'hata':
        if (m['kod'] == 'yetkisiz' || m['kod'] == 'surum') {
          // Token yanlışsa tekrar denemenin anlamı yok.
          sonHata = m['mesaj'] as String?;
          _istenen = false;
        }
    }
    _mesajlar.add(m);
  }

  void _pingAt() {
    if (DateTime.now().difference(_sonGelen) > olumSuresi) {
      sonHata = 'yer istasyonundan ${olumSuresi.inSeconds} sn yanıt yok';
      _kapandi();
      return;
    }
    gonder('ping', {'t': DateTime.now().millisecondsSinceEpoch});
  }

  void _kapandi() {
    unawaited(_temizle());
    if (_istenen) {
      _durum.value = BaglantiDurumu.hata;
      _yenidenPlanla();
    } else {
      _durum.value = sonHata != null ? BaglantiDurumu.hata : BaglantiDurumu.kopuk;
    }
  }

  void _yenidenPlanla() {
    if (!_istenen) return;
    _yenidenZamanlayici?.cancel();
    final bekle = Duration(seconds: 1 << _deneme.clamp(0, 3));
    _deneme++;
    _yenidenZamanlayici = Timer(bekle, _ac);
  }

  Future<void> _temizle() async {
    _pingZamanlayici?.cancel();
    _pingZamanlayici = null;
    _yenidenZamanlayici?.cancel();
    _yenidenZamanlayici = null;
    final abonelik = _abonelik;
    final kanal = _kanal;
    _abonelik = null;
    _kanal = null;
    pingMs = null;
    await abonelik?.cancel();
    await kanal?.sink.close();
  }

  @override
  Future<void> kopar() async {
    _istenen = false;
    sonHata = null;
    await _temizle();
    _durum.value = BaglantiDurumu.kopuk;
  }

  @override
  void gonder(String tip, [Map<String, Object?> alanlar = const {}]) {
    _kanal?.sink.add(jsonYaz(tip, alanlar));
  }

  @override
  void sesGonder(Uint8List cerceve) => _kanal?.sink.add(cerceve);

  static String _platformAdi() {
    try {
      return Platform.operatingSystem;
    } catch (_) {
      return 'telefon';
    }
  }
}
