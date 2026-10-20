/// LLM / hızlı yol JSON adımını okunur Türkçeye çevirir (kart başlığı için).
///
///   {"komut":"yuksel","metre":20}               -> "20 m yüksel"
///   {"komut":"git_yon","yon":"kuzey","metre":50} -> "kuzeye 50 m git"
/// Şema: ros2_ws/src/command_parser/command_parser/schema.py
library;

const _yonler = {
  'ileri': 'ileri',
  'geri': 'geri',
  'sag': 'sağa',
  'sol': 'sola',
  'kuzey': 'kuzeye',
  'guney': 'güneye',
  'dogu': 'doğuya',
  'bati': 'batıya',
};

String _sayi(Object? deger) {
  if (deger is! num) return '?';
  return deger == deger.roundToDouble() ? deger.toInt().toString() : deger.toString();
}

String adimAciklamasi(Map<String, dynamic> adim) {
  final komut = adim['komut'];
  final yon = _yonler[adim['yon']] ?? '${adim['yon'] ?? ''}';
  switch (komut) {
    case 'kalk':
      return adim['irtifa_m'] != null ? '${_sayi(adim['irtifa_m'])} m\'ye kalk' : 'kalk';
    case 'in':
      return 'in';
    case 'yuksel':
      return '${_sayi(adim['metre'])} m yüksel';
    case 'alcal':
      return '${_sayi(adim['metre'])} m alçal';
    case 'irtifaya_cik':
      return '${_sayi(adim['metre'])} m irtifaya git';
    case 'git_yon':
      return '$yon ${_sayi(adim['metre'])} m git';
    case 'don':
      return '$yon ${_sayi(adim['derece'])}° dön';
    case 'git_koordinat':
      return 'koordinata git (${adim['enlem']}, ${adim['boylam']})';
    case 'yakin_yere_git':
      return 'en yakın ${adim['tur']} noktasına git';
    case 'bekle':
      return '${_sayi(adim['saniye'])} sn bekle';
    case 'hiz_ayarla':
      return 'hızı ${_sayi(adim['mps'])} m/s yap';
    case 'eve_don':
      return 'eve dön';
    case 'dur':
      return 'dur';
    default:
      return '$komut';
  }
}

String adimlarAciklamasi(List<Map<String, dynamic>> adimlar) => adimlar.map(adimAciklamasi).join(' → ');

/// Komutun nereden geldiği (command_parser kaynak alanı).
String kaynakEtiketi(String? kaynak) => switch (kaynak) {
  'hizli_yol' => 'HIZLI YOL',
  'llm' => 'LLM',
  'acil' => 'ACİL',
  'onbellek' => 'ÖNBELLEK',
  'terminal' => 'TERMİNAL',
  _ => (kaynak ?? '?').toUpperCase(),
};
