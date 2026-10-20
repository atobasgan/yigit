import 'package:flutter/material.dart';

import 'durum/telsiz_kontrolcusu.dart';
import 'ekranlar/baglan_ekrani.dart';
import 'ekranlar/telsiz_ekrani.dart';

class TelsizUygulamasi extends StatelessWidget {
  const TelsizUygulamasi({super.key, required this.kontrolcu});

  final TelsizKontrolcusu kontrolcu;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drone Telsizi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B0FF), brightness: Brightness.dark),
      ),
      // Bir kez bağlandıktan sonra telsiz ekranı kalır: bağlantı koparsa istemci
      // kendiliğinden yeniden bağlanır, kullanıcı başlıkta "BAĞLANTI KOPTU" görür.
      home: ListenableBuilder(
        listenable: kontrolcu,
        builder: (context, _) =>
            kontrolcu.bagliOldu ? TelsizEkrani(kontrolcu: kontrolcu) : BaglanEkrani(kontrolcu: kontrolcu),
      ),
    );
  }
}
