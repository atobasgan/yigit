import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Köprünün terminalde gösterdiği QR kodu okur; ws://...?token=... döndürür.
class QrTarayiciEkrani extends StatefulWidget {
  const QrTarayiciEkrani({super.key});

  @override
  State<QrTarayiciEkrani> createState() => _QrTarayiciEkraniState();
}

class _QrTarayiciEkraniState extends State<QrTarayiciEkrani> {
  bool _bitti = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR kodu okut')),
      body: MobileScanner(
        onDetect: (yakalanan) {
          if (_bitti) return;
          for (final kod in yakalanan.barcodes) {
            final deger = kod.rawValue;
            if (deger != null && deger.startsWith('ws')) {
              _bitti = true;
              Navigator.of(context).pop(deger);
              return;
            }
          }
        },
      ),
    );
  }
}
