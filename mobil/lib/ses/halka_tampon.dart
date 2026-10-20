import 'dart:typed_data';

/// Son N baytı tutan halka tampon: bas-konuş tuşuna basılmadan ÖNCEKİ
/// ~300 ms'yi saklar ("ön kayıt"), böylece ilk hece kesilmez.
class HalkaTampon {
  HalkaTampon(this.kapasite) : _veri = Uint8List(kapasite);

  final int kapasite;
  final Uint8List _veri;
  int _bas = 0; // bir sonraki yazma konumu
  int _dolu = 0;

  int get uzunluk => _dolu;

  void ekle(Uint8List parca) {
    if (kapasite == 0) return;
    var kaynak = parca;
    if (kaynak.length >= kapasite) {
      kaynak = Uint8List.sublistView(kaynak, kaynak.length - kapasite);
    }
    for (final b in kaynak) {
      _veri[_bas] = b;
      _bas = (_bas + 1) % kapasite;
    }
    _dolu = (_dolu + kaynak.length).clamp(0, kapasite);
  }

  /// En eskiden en yeniye içerik (kopyalanır).
  Uint8List al() {
    final sonuc = Uint8List(_dolu);
    final baslangic = (_bas - _dolu) % kapasite;
    for (var i = 0; i < _dolu; i++) {
      sonuc[i] = _veri[(baslangic + i) % kapasite];
    }
    return sonuc;
  }

  void temizle() {
    _bas = 0;
    _dolu = 0;
  }
}
