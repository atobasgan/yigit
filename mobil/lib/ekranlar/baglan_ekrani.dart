import 'package:flutter/material.dart';

import '../ayarlar/ayarlar.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';
import '../protokol/baglanti_adresi.dart';
import 'qr_tarayici.dart';

class BaglanEkrani extends StatefulWidget {
  const BaglanEkrani({super.key, required this.kontrolcu});

  final TelsizKontrolcusu kontrolcu;

  @override
  State<BaglanEkrani> createState() => _BaglanEkraniState();
}

class _BaglanEkraniState extends State<BaglanEkrani> {
  late final TextEditingController _adres = TextEditingController(
    text: widget.kontrolcu.ayarlar.sunucuAdresi,
  );
  late final TextEditingController _token = TextEditingController(text: widget.kontrolcu.ayarlar.token);
  late bool _izleyici = widget.kontrolcu.ayarlar.izleyici;
  String? _hata;

  @override
  void dispose() {
    _adres.dispose();
    _token.dispose();
    super.dispose();
  }

  /// Faz 10: QR ekranını aç, okunan adresi bekle (`push<String>` bir Future döndürür:
  /// tarayıcı ekranı pop(deger) dediğinde tamamlanır).
  Future<void> _qrOkut() async {
    final okunan = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const QrTarayiciEkrani()));
    if (okunan == null) return; // kullanıcı geri döndü
    final a = BaglantiAdresi.coz(okunan);
    if (a == null) {
      setState(() => _hata = 'QR kodu bir telsiz adresi değil');
      return;
    }
    _adres.text = a.uri.toString();
    _token.text = a.token;
    await _baglan();
  }

  Future<void> _baglan() async {
    final adres = BaglantiAdresi.coz(_adres.text, token: _token.text);
    if (adres == null) {
      setState(() => _hata = 'Adres geçersiz. Örnek: 192.168.1.20:8765');
      return;
    }
    setState(() => _hata = null);
    final k = widget.kontrolcu;
    final yeni = k.ayarlar.copyWith(
      sunucuAdresi: adres.uri.toString(),
      token: adres.token,
      izleyici: _izleyici,
    );
    await k.ayarlariGuncelle(yeni);
    await AyarDeposu.kaydet(yeni);
    await k.baglan(adres);
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kontrolcu;
    return ListenableBuilder(
      listenable: k,
      builder: (context, _) {
        final durum = k.baglantiDurumu;
        final baglaniyor = durum == BaglantiDurumu.baglaniyor;
        final sunucuHatasi = durum == BaglantiDurumu.hata ? k.baglanti.sonHata : null;
        return Scaffold(
          appBar: AppBar(title: const Text('Drone Telsizi')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.settings_input_antenna, size: 72),
              const SizedBox(height: 12),
              const Text(
                'Yer istasyonunda köprüyü başlat:\n'
                'ros2 launch drone_bringup telsiz.launch.py\n'
                '(ROS yoksa: python3 -m mobile_bridge.deneme_sunucusu)\n'
                'Terminaldeki QR kodu okut ya da adresi yaz.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: baglaniyor ? null : _qrOkut,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('QR kodu okut'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _adres,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Yer istasyonu adresi',
                  hintText: '192.168.1.20:8765',
                ),
              ),
              TextField(
                controller: _token,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Token'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _izleyici,
                onChanged: (v) => setState(() => _izleyici = v),
                title: const Text('Sadece izle'),
                subtitle: const Text('Komut veremezsin; ACİL DUR yine çalışır'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: baglaniyor ? null : _baglan,
                child: Text(baglaniyor ? 'Bağlanıyor…' : 'Bağlan'),
              ),
              if (_hata != null || sunucuHatasi != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _hata ?? sunucuHatasi!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
