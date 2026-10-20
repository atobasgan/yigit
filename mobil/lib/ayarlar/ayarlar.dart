import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcı ayarları (telefonda saklanır). Her fazda yeni ayarlar eklenir.
class Ayarlar {
  const Ayarlar({this.sunucuAdresi = '', this.token = '', this.izleyici = false});

  final String sunucuAdresi;
  final String token;

  /// Sadece izle (komut veremez).
  final bool izleyici;

  Ayarlar copyWith({String? sunucuAdresi, String? token, bool? izleyici}) => Ayarlar(
        sunucuAdresi: sunucuAdresi ?? this.sunucuAdresi,
        token: token ?? this.token,
        izleyici: izleyici ?? this.izleyici,
      );
}

/// shared_preferences: telefonda anahtar-değer olarak kalıcı saklama
/// (Android'de SharedPreferences, iOS'ta NSUserDefaults).
class AyarDeposu {
  static Future<Ayarlar> yukle() async {
    final p = await SharedPreferences.getInstance();
    return Ayarlar(
      sunucuAdresi: p.getString('sunucuAdresi') ?? '',
      token: p.getString('token') ?? '',
      izleyici: p.getBool('izleyici') ?? false,
    );
  }

  static Future<void> kaydet(Ayarlar a) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('sunucuAdresi', a.sunucuAdresi);
    await p.setString('token', a.token);
    await p.setBool('izleyici', a.izleyici);
  }
}
