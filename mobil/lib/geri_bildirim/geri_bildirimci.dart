import 'package:flutter/services.dart';

/// Kullanıcıya dokunsal (ve Faz 10'da sesli) geri bildirim.
/// Arayüz: testlerde sahtesi kullanılır.
abstract class GeriBildirimci {
  void titresim(Titresim tur);
}

enum Titresim { basla, birak, kabul, red, acil }

/// Telefonun titreşim motoru (HapticFeedback; ek paket gerekmez).
class CihazGeriBildirimci implements GeriBildirimci {
  CihazGeriBildirimci({this.titresimAcik = true});

  bool titresimAcik;

  @override
  void titresim(Titresim tur) {
    if (!titresimAcik) return;
    switch (tur) {
      case Titresim.basla:
        HapticFeedback.mediumImpact();
      case Titresim.birak:
        HapticFeedback.lightImpact();
      case Titresim.kabul:
        HapticFeedback.selectionClick();
      case Titresim.red:
        HapticFeedback.heavyImpact();
      case Titresim.acil:
        HapticFeedback.vibrate();
    }
  }
}
