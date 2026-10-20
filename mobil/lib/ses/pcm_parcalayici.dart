import 'dart:typed_data';

import '../protokol/mesajlar.dart';

/// Mikrofondan gelen değişken boyutlu veriyi sabit 20 ms'lik (640 bayt)
/// parçalara böler. Küçük, eşit parçalar = tuş bırakıldığında yolda kalan
/// ses en az olur.
class PcmParcalayici {
  PcmParcalayici({this.parcaBoyu = parcaBayt});

  final int parcaBoyu;
  final BytesBuilder _birikim = BytesBuilder(copy: true);

  /// Tamamlanan parçaları döndürür; artan kısım bir sonraki çağrıya kalır.
  List<Uint8List> ekle(Uint8List veri) {
    _birikim.add(veri);
    if (_birikim.length < parcaBoyu) return const [];
    final hepsi = _birikim.takeBytes();
    final tamSayi = hepsi.length ~/ parcaBoyu;
    final parcalar = [
      for (var i = 0; i < tamSayi; i++) Uint8List.sublistView(hepsi, i * parcaBoyu, (i + 1) * parcaBoyu),
    ];
    if (hepsi.length > tamSayi * parcaBoyu) {
      _birikim.add(Uint8List.sublistView(hepsi, tamSayi * parcaBoyu));
    }
    return parcalar;
  }

  /// Kalan veriyi (çift bayta kırpılmış) son parça olarak verir.
  Uint8List? bosalt() {
    final kalan = _birikim.takeBytes();
    final cift = kalan.length - kalan.length % ornekBayt;
    return cift > 0 ? Uint8List.sublistView(kalan, 0, cift) : null;
  }

  void sifirla() => _birikim.clear();
}
