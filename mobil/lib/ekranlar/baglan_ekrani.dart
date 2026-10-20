import 'package:flutter/material.dart';

import '../ayarlar/ayarlar.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';
import '../protokol/baglanti_adresi.dart';

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
                'python3 -m mobile_bridge.deneme_sunucusu\n'
                'Terminaldeki adresi ve token\'ı yaz.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
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
