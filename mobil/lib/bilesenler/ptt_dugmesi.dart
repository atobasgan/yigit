import 'package:flutter/material.dart';

import '../durum/modeller.dart';

/// Büyük bas-konuş tuşu.
///
/// Listener (pointer down/up) kullanılır: GestureDetector.onLongPress
/// ~500 ms bekledikten sonra tetiklenir ve ilk kelime kaybolur.
class PttDugmesi extends StatefulWidget {
  const PttDugmesi({
    super.key,
    required this.durum,
    required this.seviye,
    required this.etkin,
    required this.basildi,
    required this.birakildi,
    required this.iptal,
    this.boyut = 132,
  });

  final PttDurumu durum;

  /// Mikrofon seviyesi 0..1 (halka kalınlığı).
  final double seviye;
  final bool etkin;
  final VoidCallback basildi;
  final VoidCallback birakildi;
  final VoidCallback iptal;
  final double boyut;

  @override
  State<PttDugmesi> createState() => _PttDugmesiState();
}

class _PttDugmesiState extends State<PttDugmesi> with SingleTickerProviderStateMixin {
  late final AnimationController _nabiz = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didUpdateWidget(covariant PttDugmesi eski) {
    super.didUpdateWidget(eski);
    if (widget.durum == PttDurumu.dinliyor) {
      if (!_nabiz.isAnimating) _nabiz.repeat();
    } else {
      _nabiz
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _nabiz.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renkler = Theme.of(context).colorScheme;
    final (renk, ikon, yazi) = switch (widget.durum) {
      PttDurumu.dinliyor => (const Color(0xFF00C853), Icons.mic, 'KONUŞ'),
      PttDurumu.isleniyor => (renkler.tertiary, Icons.hourglass_top, 'İŞLENİYOR'),
      PttDurumu.bos =>
        widget.etkin
            ? (renkler.primary, Icons.mic_none, 'BAS KONUŞ')
            : (Colors.grey.shade700, Icons.mic_off, 'BAĞLI DEĞİL'),
    };
    final b = widget.boyut;
    return Semantics(
      button: true,
      label: 'Bas konuş tuşu',
      child: Listener(
        onPointerDown: widget.etkin ? (_) => widget.basildi() : null,
        onPointerUp: widget.etkin ? (_) => widget.birakildi() : null,
        onPointerCancel: widget.etkin ? (_) => widget.iptal() : null,
        child: AnimatedBuilder(
          animation: _nabiz,
          builder: (context, _) {
            final dinliyor = widget.durum == PttDurumu.dinliyor;
            return SizedBox(
              width: b * 1.6,
              height: b * 1.6,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (dinliyor)
                    Container(
                      width: b * (1 + 0.5 * _nabiz.value),
                      height: b * (1 + 0.5 * _nabiz.value),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: renk.withValues(alpha: 1 - _nabiz.value), width: 3),
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: b,
                    height: b,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: renk,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.85),
                        width: dinliyor ? 3 + 14 * widget.seviye : 2,
                      ),
                      boxShadow: [BoxShadow(color: renk.withValues(alpha: 0.5), blurRadius: 24)],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(ikon, size: b * 0.36, color: Colors.white),
                        Text(
                          yazi,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
