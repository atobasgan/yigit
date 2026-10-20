import 'package:flutter/material.dart';

import 'app.dart';
import 'ayarlar/ayarlar.dart';
import 'baglanti/telsiz_istemcisi.dart';
import 'durum/telsiz_kontrolcusu.dart';
import 'protokol/baglanti_adresi.dart';

Future<void> main() async {
  // runApp'ten önce eklenti (shared_preferences) kullanacaksak gerekli.
  WidgetsFlutterBinding.ensureInitialized();
  final ayarlar = await AyarDeposu.yukle();
  final kontrolcu = TelsizKontrolcusu(baglanti: TelsizIstemcisi(), ayarlar: ayarlar);
  runApp(TelsizUygulamasi(kontrolcu: kontrolcu));

  // Son kullanılan yer istasyonuna kendiliğinden bağlan.
  final son = BaglantiAdresi.coz(ayarlar.sunucuAdresi, token: ayarlar.token);
  if (son != null && son.token.isNotEmpty) await kontrolcu.baglan(son);
}
