import 'package:flutter/material.dart';

import '../bilesenler/acil_dur_dugmesi.dart';
import '../bilesenler/konusma_karti.dart';
import '../bilesenler/ptt_dugmesi.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';

/// Hızlı tuşlar da METİN olarak gider ve command_parser'dan geçer:
/// telefon komutu kendisi yorumlamaz, güvenlik katmanı her zaman çalışır.
const hizliKomutlar = ['kalk', 'in', 'eve dön', '10 metre yüksel', 'sağa dön', '5 saniye bekle'];

/// Faz 5: Komut kartları, hızlı tuşlar ve yazılı komut.
class TelsizEkrani extends StatefulWidget {
  const TelsizEkrani({super.key, required this.kontrolcu});

  final TelsizKontrolcusu kontrolcu;

  @override
  State<TelsizEkrani> createState() => _TelsizEkraniState();
}

class _TelsizEkraniState extends State<TelsizEkrani> {
  final _metin = TextEditingController();
  PttDurumu _ptt = PttDurumu.bos;

  @override
  void dispose() {
    _metin.dispose();
    super.dispose();
  }

  void _gonder() {
    widget.kontrolcu.metinGonder(_metin.text);
    _metin.clear();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kontrolcu;
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
                onBasildi: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('ACİL DUR Faz 6\'da yer istasyonuna gidecek'))),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (k.bildirim != null)
              MaterialBanner(
                content: Text(k.bildirim!),
                actions: [TextButton(onPressed: k.bildirimiKapat, child: const Text('Tamam'))],
              ),
            Expanded(
              child: k.kartlar.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Komut yaz ya da hızlı tuşa bas.\nÖrnek: "önce 20 metre yüksel sonra kuzeye 50 metre git"',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 6, bottom: 12),
                      itemCount: k.kartlar.length,
                      itemBuilder: (_, i) => KonusmaKartiGorunumu(kart: k.kartlar[i]),
                    ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final komut in hizliKomutlar)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        label: Text(komut),
                        onPressed: k.komutVerebilir ? () => k.metinGonder(komut, giris: 'hizli_tus') : null,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextField(
                controller: _metin,
                enabled: k.komutVerebilir,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _gonder(),
                decoration: InputDecoration(
                  hintText: 'komut yaz (ör. 50 metreye çık)',
                  suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _gonder),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: PttDugmesi(
                durum: _ptt,
                seviye: 0,
                etkin: k.komutVerebilir,
                basildi: () => setState(() => _ptt = PttDurumu.dinliyor),
                birakildi: () {
                  setState(() => _ptt = PttDurumu.bos);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sesli komut Faz 7\'de. Şimdilik yaz ya da hızlı tuşa bas.'),
                    ),
                  );
                },
                iptal: () => setState(() => _ptt = PttDurumu.bos),
              ),
            ),
          ],
        ),
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
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: renk),
        const SizedBox(width: 6),
        Flexible(child: Text(yazi, overflow: TextOverflow.ellipsis)),
        if (ping != null) ...[
          const SizedBox(width: 8),
          Text('$ping ms', style: Theme.of(context).textTheme.labelMedium),
        ],
      ],
    );
  }
}
