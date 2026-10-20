import 'dart:math' as math;
import 'dart:typed_data';

/// PCM16 parçasının ses seviyesi, arayüz için 0..1 (yaklaşık -60..0 dBFS).
double sesSeviyesi(Uint8List pcm) {
  final n = pcm.length ~/ 2;
  if (n == 0) return 0;
  final veri = ByteData.sublistView(pcm);
  var toplam = 0.0;
  for (var i = 0; i < n; i++) {
    final o = veri.getInt16(i * 2, Endian.little);
    toplam += o * o;
  }
  final rms = math.sqrt(toplam / n) / 32768.0;
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 60) / 60).clamp(0.0, 1.0);
}
