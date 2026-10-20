import 'package:flutter/material.dart';

import '../bilesenler/acil_dur_dugmesi.dart';
import '../bilesenler/ptt_dugmesi.dart';
import '../durum/modeller.dart';

/// Faz 1: Telsiz ekranının iskeleti.
///
/// Henüz bağlantı, mikrofon ya da yer istasyonu yok. Tuşa basıp bırakınca
/// ne kadar basılı tutulduğu listeye yazılır; böylece bas-konuş tuşunun
/// "dokunduğun anda" tepki verdiğini görebilirsin.
class TelsizEkrani extends StatefulWidget {
  const TelsizEkrani({super.key});

  @override
  State<TelsizEkrani> createState() => _TelsizEkraniState();
}

class _TelsizEkraniState extends State<TelsizEkrani> {
  PttDurumu _ptt = PttDurumu.bos;
  DateTime? _basma;
  final List<String> _gecmis = [];

  void _basildi() {
    setState(() {
      _ptt = PttDurumu.dinliyor;
      _basma = DateTime.now();
    });
  }

  void _birakildi() {
    final sure = DateTime.now().difference(_basma ?? DateTime.now()).inMilliseconds;
    setState(() {
      _ptt = PttDurumu.bos;
      _gecmis.insert(0, 'Konuşma ${_gecmis.length + 1}: $sure ms basılı tutuldu');
    });
  }

  void _iptal() => setState(() => _ptt = PttDurumu.bos);

  void _acilDur() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ACİL DUR — yer istasyonu bağlantısı Faz 6\'da gelecek')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drone Telsizi'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: AcilDurDugmesi(onBasildi: _acilDur),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _gecmis.isEmpty
              ? const Center(child: Text('Tuşa basılı tut, sonra bırak.'))
              : ListView(children: [for (final satir in _gecmis) ListTile(title: Text(satir))]),
        ),
        SafeArea(
          top: false,
          child: PttDugmesi(
            durum: _ptt,
            seviye: 0,
            etkin: true,
            basildi: _basildi,
            birakildi: _birakildi,
            iptal: _iptal,
          ),
        ),
      ]),
    );
  }
}
