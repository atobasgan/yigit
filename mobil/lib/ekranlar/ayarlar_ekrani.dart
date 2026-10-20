import 'package:flutter/material.dart';

import '../ayarlar/ayarlar.dart';
import '../durum/modeller.dart';
import '../durum/telsiz_kontrolcusu.dart';

class AyarlarEkrani extends StatelessWidget {
  const AyarlarEkrani({super.key, required this.kontrolcu});

  final TelsizKontrolcusu kontrolcu;

  Future<void> _degistir(Ayarlar yeni) async {
    await kontrolcu.ayarlariGuncelle(yeni);
    await AyarDeposu.kaydet(yeni);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: kontrolcu,
      builder: (context, _) {
        final a = kontrolcu.ayarlar;
        final stt = kontrolcu.yerSttVar
            ? 'yer istasyonunda STT var (${kontrolcu.sttMotoru})'
            : 'yer istasyonunda STT yok';
        return Scaffold(
          appBar: AppBar(title: const Text('Ayarlar')),
          body: ListView(
            children: [
              const _Baslik('Konuşma tanıma'),
              RadioGroup<SttModu>(
                groupValue: a.sttModu,
                onChanged: (m) => _degistir(a.copyWith(sttModu: m)),
                child: Column(
                  children: [
                    for (final mod in SttModu.values)
                      RadioListTile<SttModu>(
                        value: mod,
                        title: Text(switch (mod) {
                          SttModu.otomatik => 'Otomatik',
                          SttModu.telefon => 'Telefonda tanı',
                          SttModu.yer => 'Yer istasyonunda tanı',
                        }),
                        subtitle: Text(switch (mod) {
                          SttModu.otomatik => 'Varsa yer istasyonu, yoksa telefon ($stt)',
                          SttModu.telefon => 'Telefonun Türkçe tanıyıcısı; sadece metin gönderilir',
                          SttModu.yer => 'Ham ses akar; faster-whisper ile daha doğru, ölçülebilir',
                        }),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                value: a.cevrimdisiTanima,
                onChanged: (v) => _degistir(a.copyWith(cevrimdisiTanima: v)),
                title: const Text('Telefonda internetsiz tanıma'),
                subtitle: const Text('Cihaz Türkçe çevrimdışı paketini desteklemiyorsa hata verir'),
              ),
              const _Baslik('Ses (yer istasyonu modu)'),
              SwitchListTile(
                value: a.onKayit,
                onChanged: (v) => _degistir(a.copyWith(onKayit: v)),
                title: const Text('Ön kayıt (300 ms)'),
                subtitle: const Text(
                  'İlk hece kesilmesin diye mikrofon açık kalır; ses telefondan '
                  'yalnızca tuşa basınca çıkar',
                ),
              ),
              ListTile(
                title: const Text('Son kayıt'),
                subtitle: Text('Tuşu bıraktıktan sonra ${a.sonKayitMs} ms daha kaydet'),
                trailing: SizedBox(
                  width: 160,
                  child: Slider(
                    value: a.sonKayitMs.toDouble(),
                    min: 0,
                    max: 400,
                    divisions: 8,
                    label: '${a.sonKayitMs} ms',
                    onChanged: (v) => _degistir(a.copyWith(sonKayitMs: v.round())),
                  ),
                ),
              ),
              SwitchListTile(
                value: a.gurultuBastirma,
                onChanged: (v) => _degistir(a.copyWith(gurultuBastirma: v)),
                title: const Text('Gürültü bastırma'),
                subtitle: const Text('Rüzgârlı sahada dene; STT doğruluğunu ölçerek karar ver'),
              ),
              const _Baslik('Geri bildirim'),
              SwitchListTile(
                value: a.sesliYanit,
                onChanged: (v) => _degistir(a.copyWith(sesliYanit: v)),
                title: const Text('Sesli yanıt (Türkçe TTS)'),
              ),
              SwitchListTile(
                value: a.titresim,
                onChanged: (v) => _degistir(a.copyWith(titresim: v)),
                title: const Text('Titreşim'),
              ),
              const _Baslik('Bağlantı'),
              ListTile(
                title: Text(a.sunucuAdresi.isEmpty ? '–' : a.sunucuAdresi),
                subtitle: Text(kontrolcu.bagli ? 'bağlı (${kontrolcu.rol})' : 'bağlı değil'),
                trailing: TextButton(
                  onPressed: () async {
                    await kontrolcu.kopar();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: const Text('Bağlantıyı kes'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Baslik extends StatelessWidget {
  const _Baslik(this.yazi);

  final String yazi;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      yazi.toUpperCase(),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 1.2),
    ),
  );
}
