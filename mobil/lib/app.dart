import 'package:flutter/material.dart';

import 'ekranlar/telsiz_ekrani.dart';

class TelsizUygulamasi extends StatelessWidget {
  const TelsizUygulamasi({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drone Telsizi',
      debugShowCheckedModeBanner: false,
      // Sahada güneş altında okunaklı: koyu, yüksek kontrastlı tema.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00B0FF), brightness: Brightness.dark),
      ),
      home: const TelsizEkrani(),
    );
  }
}
