import 'package:flutter/material.dart';

import '../bilesenler/acil_dur_dugmesi.dart';
import '../bilesenler/ptt_dugmesi.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';

/// Faz 4: Telsiz ekranı artık bağlantı durumunu gösteriyor.
/// Bas-konuş hâlâ yerel bir deneme (konuşma Faz 7'de gelecek).
class TelsizEkrani extends StatefulWidget {
  const TelsizEkrani({super.key, required this.kontrolcu});

  final TelsizKontrolcusu kontrolcu;

  @override
  State<TelsizEkrani> createState() => _TelsizEkraniState();
}

class _TelsizEkraniState extends State<TelsizEkrani> {
  PttDurumu _ptt = PttDurumu.bos;
  DateTime? _basma;
  final List<String> _gecmis = [];

  void _basildi() => setState(() {
        _ptt = PttDurumu.dinliyor;
        _basma = DateTime.now();
      });

  void _birakildi() {
    final sure = DateTime.now().difference(_basma ?? DateTime.now()).inMilliseconds;
    setState(() {
      _ptt = PttDurumu.bos;
      _gecmis.insert(0, 'Konuşma ${_gecmis.length + 1}: $sure ms basılı tutuldu');
    });
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kontrolcu;
    // ListenableBuilder: kontrolcü notifyListeners() dedikçe bu kısım yeniden çizilir.
    return ListenableBuilder(
      listenable: k,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: BaglantiBasligi(k: k),
          actions: [
            IconButton(tooltip: 'Bağlantıyı kes', icon: const Icon(Icons.link_off), onPressed: k.kopar),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AcilDurDugmesi(
                etkin: k.bagli,
                onBasildi: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ACİL DUR Faz 6\'da yer istasyonuna gidecek')),
                ),
              ),
            ),
          ],
        ),
        body: Column(children: [
          if (k.bildirim != null)
            MaterialBanner(
              content: Text(k.bildirim!),
              actions: [TextButton(onPressed: k.bildirimiKapat, child: const Text('Tamam'))],
            ),
          Expanded(
            child: _gecmis.isEmpty
                ? const Center(child: Text('Bağlandın. Bas-konuş Faz 7\'de yer istasyonuna gidecek.'))
                : ListView(children: [for (final s in _gecmis) ListTile(title: Text(s))]),
          ),
          SafeArea(
            top: false,
            child: PttDugmesi(
              durum: _ptt,
              seviye: 0,
              etkin: k.komutVerebilir,
              basildi: _basildi,
              birakildi: _birakildi,
              iptal: () => setState(() => _ptt = PttDurumu.bos),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Bağlantı rozeti: renkli nokta + rol + ping.
class BaglantiBasligi extends StatelessWidget {
  const BaglantiBasligi({super.key, required this.k});

  final TelsizKontrolcusu k;

  @override
  Widget build(BuildContext context) {
    final (renk, yazi) = switch (k.baglantiDurumu) {
      BaglantiDurumu.bagli => (const Color(0xFF00C853), k.rol == 'operator' ? 'OPERATÖR' : 'İZLEYİCİ'),
      BaglantiDurumu.baglaniyor => (Colors.amber, 'BAĞLANIYOR'),
      BaglantiDurumu.hata => (Colors.red, 'BAĞLANTI KOPTU'),
      BaglantiDurumu.kopuk => (Colors.grey, 'KOPUK'),
    };
    final ping = k.baglanti.pingMs;
    return Row(children: [
      Icon(Icons.circle, size: 12, color: renk),
      const SizedBox(width: 6),
      Flexible(child: Text(yazi, overflow: TextOverflow.ellipsis)),
      if (ping != null) ...[
        const SizedBox(width: 8),
        Text('$ping ms', style: Theme.of(context).textTheme.labelMedium),
      ],
    ]);
  }
}
