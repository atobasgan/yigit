import 'package:flutter/material.dart';

import '../durum/modeller.dart';

class TelemetriSeridi extends StatelessWidget {
  const TelemetriSeridi({super.key, required this.telemetri});

  final Telemetri telemetri;

  @override
  Widget build(BuildContext context) {
    final t = telemetri;
    if (!t.hazir) {
      return const _Serit(children: [Text('telemetri bekleniyor (PX4 bağlı mı?)')]);
    }
    String f(double? d, [int basamak = 1]) => d == null ? '–' : d.toStringAsFixed(basamak);
    final batarya = t.batarya;
    return _Serit(
      children: [
        _Deger('İRTİFA', '${f(t.irtifa)} m'),
        _Deger('HIZ', '${f(t.hiz)} m/s'),
        _Deger('YÖN', '${f(t.yaw, 0)}°'),
        _Deger(
          'BATARYA',
          batarya == null ? '–' : '%${(batarya * 100).round()}',
          uyari: batarya != null && batarya < 0.3,
        ),
        _Deger('MOD', t.mod ?? '–'),
        _Deger(t.arm ? 'ARM' : 'DISARM', t.havada ? 'HAVADA' : 'YERDE'),
      ],
    );
  }
}

class _Serit extends StatelessWidget {
  const _Serit({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Wrap(spacing: 16, runSpacing: 6, alignment: WrapAlignment.spaceBetween, children: children),
    );
  }
}

class _Deger extends StatelessWidget {
  const _Deger(this.etiket, this.deger, {this.uyari = false});

  final String etiket;
  final String deger;
  final bool uyari;

  @override
  Widget build(BuildContext context) {
    final stil = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(etiket, style: stil.labelSmall?.copyWith(letterSpacing: 1)),
        Text(
          deger,
          style: stil.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: uyari ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}
