import 'package:flutter/material.dart';

import '../durum/komut_aciklama.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';

/// Bir konuşmanın tüm hattı: duyulan -> (normalize) -> JSON komut -> yürütme.
/// Operatör "yanlış mı duydu, yanlış mı anladı" ayrımını buradan görür.
class KonusmaKartiGorunumu extends StatelessWidget {
  const KonusmaKartiGorunumu({super.key, required this.kart});

  final KonusmaKarti kart;

  @override
  Widget build(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    final stil = Theme.of(context).textTheme;
    final (renk, durumYazi) = _durumGorunumu(kart.durum, renkler);
    final girisIkonu = switch (kart.giris) {
      'ses' => Icons.mic,
      'klavye' => Icons.keyboard,
      'hizli_tus' => Icons.touch_app,
      _ => Icons.person_outline,
    };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: renk, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(girisIkonu, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    TelsizKontrolcusu.kartBasligi(kart),
                    style: stil.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _Rozet(durumYazi, renk),
              ],
            ),
            if (kart.duyulan != null) ...[
              const SizedBox(height: 6),
              _Satir('duyulan', '"${kart.duyulan}"', ek: _sttEki()),
            ],
            if (kart.normalize != null && kart.normalize != kart.duyulan)
              _Satir('normalize', kart.normalize!),
            if (kart.adimlar.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  _Rozet(kaynakEtiketi(kart.komutKaynagi), renkler.secondary),
                  if (kart.kuyrugaEklendi) ...[const SizedBox(width: 6), _Rozet('KUYRUĞA', renkler.outline)],
                  const Spacer(),
                  if (kart.toplamGecikmeMs != null)
                    Text('${kart.toplamGecikmeMs} ms', style: stil.labelMedium),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: renkler.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  kart.komutJson,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                ),
              ),
            ],
            if (kart.sebep != null) ...[
              const SizedBox(height: 6),
              Text(kart.sebep!, style: stil.bodyMedium?.copyWith(color: renkler.error)),
            ],
            for (final olay in kart.olaylar.reversed.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('• $olay', style: stil.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  String? _sttEki() {
    final kaynak = switch (kart.sttKaynagi) {
      'yer_stt' => 'yer STT',
      'telefon_stt' => 'telefon STT',
      'klavye' => 'klavye',
      'hizli_tus' => 'hızlı tuş',
      final k => k,
    };
    if (kaynak == null) return null;
    return kart.sttMs != null ? '$kaynak · ${kart.sttMs} ms' : kaynak;
  }

  static (Color, String) _durumGorunumu(KartDurumu d, ColorScheme r) => switch (d) {
    KartDurumu.dinleniyor => (const Color(0xFF00C853), 'DİNLENİYOR'),
    KartDurumu.isleniyor => (r.tertiary, 'İŞLENİYOR'),
    KartDurumu.duyuldu => (r.tertiary, 'DUYULDU'),
    KartDurumu.komut => (r.primary, 'KOMUT'),
    KartDurumu.yurutuyor => (r.primary, 'YÜRÜTÜYOR'),
    KartDurumu.tamamlandi => (const Color(0xFF2E7D32), 'TAMAM'),
    KartDurumu.reddedildi => (r.error, 'REDDEDİLDİ'),
    KartDurumu.anlasilmadi => (Colors.orange, 'ANLAŞILMADI'),
  };
}

class _Satir extends StatelessWidget {
  const _Satir(this.etiket, this.deger, {this.ek});

  final String etiket;
  final String deger;
  final String? ek;

  @override
  Widget build(BuildContext context) {
    final stil = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 78, child: Text(etiket, style: stil.labelMedium)),
          Expanded(child: Text(deger, style: stil.bodyMedium)),
          if (ek != null) Text(ek!, style: stil.labelSmall),
        ],
      ),
    );
  }
}

class _Rozet extends StatelessWidget {
  const _Rozet(this.yazi, this.renk);

  final String yazi;
  final Color renk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: renk.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: renk),
      ),
      child: Text(
        yazi,
        style: TextStyle(color: renk, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}
