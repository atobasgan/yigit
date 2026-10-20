import 'package:flutter/material.dart';

import '../bilesenler/acil_dur_dugmesi.dart';
import '../bilesenler/konusma_karti.dart';
import '../bilesenler/ptt_dugmesi.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';

/// Hızlı tuşlar da METİN olarak gider ve command_parser'dan geçer:
/// telefon komutu kendisi yorumlamaz, güvenlik katmanı her zaman çalışır.
const hizliKomutlar = ['kalk', 'in', 'eve dön', '10 metre yüksel', 'sağa dön', '5 saniye bekle'];

/// Faz 5: Komut kartları, hızlı tuşlar ve yazılı komut. Faz 6: ACİL DUR.
/// Faz 7: bas-konuş (telefonda tanıma). Faz 8: ham ses (yer STT).
class TelsizEkrani extends StatefulWidget {
  const TelsizEkrani({super.key, required this.kontrolcu});

  final TelsizKontrolcusu kontrolcu;

  @override
  State<TelsizEkrani> createState() => _TelsizEkraniState();
}

class _TelsizEkraniState extends State<TelsizEkrani> {
  final _metin = TextEditingController();

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
              child: AcilDurDugmesi(onBasildi: k.acilDur, etkin: k.bagli),
            ),
          ],
        ),
        body: Column(
          children: [
            if (k.bildirim != null)
              MaterialBanner(
                content: Text(k.bildirim!),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                actions: [TextButton(onPressed: k.bildirimiKapat, child: const Text('Tamam'))],
              ),
            Expanded(
              child: k.kartlar.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Tuşa basılı tut, konuş, bırak. Ya da yaz / hızlı tuşa bas.\nÖrnek: "önce 20 metre yüksel sonra kuzeye 50 metre git"',
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
            // Konuşurken telefonun tanıyıcısının ara sonucu (canlı altyazı gibi)
            if (k.kismiMetin != null && k.kismiMetin!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('"${k.kismiMetin}"', style: Theme.of(context).textTheme.titleMedium),
              ),
            SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 72),
                  PttDugmesi(
                    durum: k.ptt,
                    seviye: k.seviye, // mikrofon seviyesi: halka kalınlığı
                    etkin: k.komutVerebilir,
                    basildi: k.pttBasla,
                    birakildi: k.pttBirak,
                    iptal: k.pttIptal,
                  ),
                  // Hangi modda tanınıyor? (Faz 8: otomatik seçim)
                  SizedBox(
                    width: 72,
                    child: Text(
                      k.etkinMod == SttModu.yer ? 'yer\nSTT' : 'telefon\nSTT',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
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
