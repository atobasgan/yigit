/// Bağlantı adresi: QR koddan ya da elle girilen metinden çözülür.
///
/// Kabul edilenler:
///   ws://192.168.1.5:8765/telsiz?token=ABC   (köprünün QR kodu)
///   192.168.1.5:8765                         (token ayrıca girilir)
///   192.168.1.5                              (port 8765 varsayılır)
library;

class BaglantiAdresi {
  const BaglantiAdresi({required this.uri, required this.token});

  static const int varsayilanPort = 8765;
  static const String varsayilanYol = '/telsiz';

  /// Token içermeyen WebSocket adresi.
  final Uri uri;
  final String token;

  /// QR / paylaşım için tam metin.
  String get tamMetin => uri.replace(queryParameters: {'token': token}).toString();

  /// [girdi] çözülemezse null. [token] verilirse adresteki token'ın yerine geçer.
  static BaglantiAdresi? coz(String girdi, {String? token}) {
    var metin = girdi.trim();
    if (metin.isEmpty) return null;
    if (!metin.contains('://')) metin = 'ws://$metin';
    final Uri ham;
    try {
      ham = Uri.parse(metin);
    } on FormatException {
      return null;
    }
    if (!(ham.scheme == 'ws' || ham.scheme == 'wss') || ham.host.isEmpty) return null;
    final secilenToken = (token != null && token.trim().isNotEmpty)
        ? token.trim()
        : (ham.queryParameters['token'] ?? '');
    final uri = Uri(
      scheme: ham.scheme,
      host: ham.host,
      port: ham.hasPort ? ham.port : varsayilanPort,
      path: (ham.path.isEmpty || ham.path == '/') ? varsayilanYol : ham.path,
    );
    return BaglantiAdresi(uri: uri, token: secilenToken);
  }

  @override
  bool operator ==(Object other) => other is BaglantiAdresi && other.uri == uri && other.token == token;

  @override
  int get hashCode => Object.hash(uri, token);
}
