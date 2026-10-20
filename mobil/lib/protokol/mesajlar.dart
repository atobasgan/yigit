/// Telsiz protokolü, sürüm 1 (yer istasyonu: ros2_ws/src/mobile_bridge/protokol.py).
///
/// Tek WebSocket bağlantısı:
///   - metin çerçevesi = JSON kontrol mesajı, her mesajda "tip" alanı
///   - ikili çerçeve   = ses parçası: [uint32 id][uint32 sıra][PCM16 LE mono]
library;

import 'dart:convert';
import 'dart:typed_data';

const int protokolSurumu = 1;
const int orneklemeHz = 16000;
const int ornekBayt = 2;

/// 20 ms'lik ses parçası: 16000 Hz x 0.02 s x 2 bayt = 640 bayt.
const int parcaBayt = orneklemeHz * ornekBayt ~/ 50;

/// Milisaniyeyi PCM16 bayt sayısına çevirir (çift sayı).
int msToBayt(int ms) => orneklemeHz * ornekBayt * ms ~/ 1000 ~/ 2 * 2;

String jsonYaz(String tip, [Map<String, Object?> alanlar = const {}]) => jsonEncode({'tip': tip, ...alanlar});

/// Sunucudan gelen metni çözer; geçersizse null.
Map<String, dynamic>? jsonCoz(Object? ham) {
  if (ham is! String) return null;
  try {
    final m = jsonDecode(ham);
    if (m is Map<String, dynamic> && m['tip'] is String) return m;
  } on FormatException {
    return null;
  }
  return null;
}

/// İkili ses çerçevesi: 8 baytlık başlık + PCM.
Uint8List sesParcasi(int konusmaId, int sira, Uint8List pcm) {
  final cerceve = Uint8List(8 + pcm.length);
  ByteData.sublistView(cerceve)
    ..setUint32(0, konusmaId, Endian.little)
    ..setUint32(4, sira, Endian.little);
  cerceve.setRange(8, cerceve.length, pcm);
  return cerceve;
}
