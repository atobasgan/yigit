# Faz 8 — Ham ses akışı: PCM, 20 ms parçalar, ön kayıt

> **Bu fazın sonunda:** "Yer STT" modunda telefon sesi yazıya **çevirmiyor**.
> Ham sesi, tuş basılıyken 20 ms'lik parçalar halinde yer istasyonuna akıtıyor.
> Köprü parçaları birleştirip STT'ye veriyor (bu fazda sahte bir STT, gerçek
> Whisper Faz 9'da). İlk hecenin kesilmemesi için 300 ms **ön kayıt**, son
> hece için 150 ms **son kayıt** var. Uygulama, yer istasyonunda STT varsa bu
> modu kendiliğinden seçiyor.

## 1. Neden sesi göndermek isteyelim?

Faz 7'de telefon sesi kendisi yazıya çeviriyordu. Ama:

- Telefonların Türkçe tanıması cihaza ve işletim sistemine göre çok değişir.
- O tanıyıcıyı ne iyileştirebiliriz ne de ölçebiliriz.

Ses yer istasyonuna giderse STT bizim kontrolümüzde olur. Hangi modelin
kullanılacağına biz karar veririz, drone sözlüğünü veririz, kayıtlarla ölçeriz,
gerekirse kendi verimizle eğitiriz. Drone reposundaki Faz 3-4'ün mantığı bu.

## 2. Dijital ses: 5 dakikalık özet

Mikrofon havadaki basınç dalgasını bir elektrik sinyaline çevirir. Telefon bu
sinyalin değerini saniyede binlerce kez ölçer (**örnekleme**):

```
basınç
  ^     .-.         .-.
  |   .'   '.     .'   '.        her nokta = bir örnek (sample)
  |--'-------'---'-------'---->  zaman
          ↑ ↑ ↑ ↑ ↑ ↑ ↑ ↑         16 000 örnek / saniye
```

| Kavram | Bizdeki değer | Anlamı |
|---|---|---|
| Örnekleme hızı | **16 000 Hz** | Saniyede 16 bin ölçüm. Konuşma için yeterli; Whisper bu hızı bekler. (Müzik 44 100 Hz kullanır.) |
| Örnek boyutu | **16 bit** (PCM16) | Her ölçüm −32768…+32767 arası bir tam sayı = 2 bayt |
| Kanal | **mono** | Tek mikrofon; stereoya gerek yok |
| Kodlama | **PCM** | Sıkıştırma yok, ham sayılar |

**Bant hesabı** (bunu kafadan yapabilmek önemli):

```
16 000 örnek/sn × 2 bayt × 1 kanal = 32 000 bayt/sn ≈ 32 KB/sn
3 sn'lik komut ≈ 96 KB
20 ms'lik parça = 16 000 × 0.02 × 2 = 640 bayt
```

Ev ya da saha Wi-Fi'ı saniyede onlarca **mega**bayt taşır; 32 KB/sn hiçbir
şey değildir. Bu yüzden **sıkıştırma yapmıyoruz**. Sıkıştırma (ör. Opus) hem
gecikme ekler hem kalite kaybettirir. Ancak mobil veri ya da VPN gibi yavaş
bir bağlantıda düşünülmeli.

## 3. Mikrofonu açmak: `record` paketi

```dart
await _kayitci.startStream(RecordConfig(
  encoder: AudioEncoder.pcm16bits,   // ham PCM16
  sampleRate: 16000,
  numChannels: 1,
  androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
));
```

Android'de `VOICE_RECOGNITION` ses kaynağı **konuşma tanıma için ayarlanmış**
mikrofon yoludur; işletim sisteminin müzik ya da telefon görüşmesi için
yaptığı işlemleri (yankı giderme vb.) atlar. Gürültü bastırma ayardan açılıp
kapatılabilir (`gurultuBastirma`). Hangisinin daha iyi olduğuna sahada,
ölçerek karar verilmeli.

## 4. 20 ms'lik parçalar (`pcm_parcalayici.dart`)

Mikrofon veriyi kendi seçtiği boyutlarda verir (bazen 1 KB, bazen 4 KB). Biz bunu
**sabit 640 baytlık** parçalara bölüyoruz:

```
mikrofon:  [ 1500 bayt        ][ 900 bayt  ]...
parçalar:  [640][640]  (220 bekler) -> [640][640]...
```

**Neden küçük ve eşit parçalar?** Tuşu bıraktığın anda yer istasyonunda sesin
neredeyse tamamı **zaten var**; yolda en fazla bir parça (20 ms) kalır.
"Önce bütün sesi kaydet, sonra dosyayı gönder" yaklaşımına göre yüzlerce ms
kazandırır.

## 5. Ön kayıt: halka tampon (`halka_tampon.dart`)

İnsanlar tuşa **basarken** konuşmaya başlar. Mikrofon tuşla açılırsa ilk hece
("yir-" mi metre yüksel) kaybolur. Çözüm şu: yer STT modunda mikrofon **hep
açık**, ama son 300 ms'yi bir **halka tamponda** tutar:

```
kapasite = 9600 bayt (300 ms)
 ┌───┬───┬───┬───┬───┬───┐
 │ 4 │ 5 │ 6 │ 1 │ 2 │ 3 │   yeni veri en eskinin üstüne yazılır
 └───┴───┴───┴───┴───┴───┘
               ^ en eski (_bas - _dolu)
```

Tuşa basılınca tamponun içeriği **ilk parçalar** olarak gönderilir, sonra
canlı ses gelir. Tampon dolunca en eski veri ezilir; bellek hiç büyümez.

**Gizlilik:** Ses telefondan **yalnızca tuş basılıyken** çıkar. Test bunu bayt
bayt doğruluyor:

```dart
o.m.besle(1000, deger: 7);              // tuştan önce 1 sn ses
expect(o.b.ses, isEmpty);               // -> sunucuya 0 bayt
await o.k.pttBasla(); o.m.besle(1000, deger: 9); await o.k.pttBirak();
expect(onKayit, 9600);                  // tam 300 ms ön kayıt
expect(toplam, 9600 + 32000);           // + 1 sn canlı ses
```

(Telefon, mikrofon açıkken üst köşede bir gösterge yakar. Ayardan
`onKayit: false` yapılırsa mikrofon yalnızca tuşla açılır.)

**Son kayıt:** Tuş bırakıldıktan sonra 150 ms daha kayıt alınır, sonra
`ptt_bitti` gönderilir. İnsanlar son heceyi bitirmeden tuşu bırakma eğilimindedir.

## 6. Kablo üzerindeki konuşma

```
{"tip":"ptt_basla","id":42}
<ikili> [42][0][640 bayt]   <- ön kayıt
<ikili> [42][1][640 bayt]
...                          <- canlı ses, 20 ms'de bir
<ikili> [42][67][640 bayt]  <- son kayıt
{"tip":"ptt_bitti","id":42,"parca_sayisi":68}
          köprü -> {"tip":"isleniyor","id":42,"sure_ms":1360,"kayip_parca":0}
          köprü -> STT (ayrı thread) -> {"tip":"duyuldu","id":42,"kaynak":"yer_stt",...}
          köprü -> /voice/text -> Faz 5 yolu -> {"tip":"komut",...}
```

## 7. Köprü tarafı (`cekirdek.py`, `ses.py`)

- `ptt_basla` → `Konusma` nesnesi açılır.
- İkili çerçeve → `Konusma.ekle(sira, pcm)`. Parçalar **sıra numarasına göre** tutulur (sözlük). Ağda sırası karışsa da `pcm()` doğru sırayla birleştirir. Aynı parça iki kez gelirse yok sayılır. Eksik sıra numaraları `kayip_parca` olarak bildirilir.
- Sınırlar: 15 sn'den uzun konuşma kesilir (tuş takılı kalmasın, bellek dolmasın). 250 ms'den kısa konuşma "çok kısa" diye reddedilir.
- Yalnızca **operatörün** sesi alınır; izleyicinin ikili çerçeveleri yok sayılır.
- `ptt_bitti` → STT **ayrı bir thread'de** çalışır (`stt_baslat`). Sonuç `sunucu.disaridan()` ile olay döngüsüne döner. STT saniyeler sürebilir; bu sırada ACİL DUR beklememeli (Faz 6'daki ders).
- Sunucuda STT yoksa telefona "telefonda tanı moduna geç" denir.

## 8. Telefon tarafı: iki mod, otomatik seçim

```dart
SttModu get etkinMod => switch (ayarlar.sttModu) {
  SttModu.otomatik => yerSttVar ? SttModu.yer : SttModu.telefon,   // hos_geldin'deki yer_stt
  final m => m,
};
```

Bas-konuş tuşunun yanında hangi modun etkin olduğu yazar (`yer STT` /
`telefon STT`). Tuş halkasının kalınlığı mikrofon seviyesini gösterir
(`seviye.dart`: RMS → dBFS → 0..1). Kullanıcı mikrofonun gerçekten duyduğunu
görür.

## 9. Dene

```bash
cd kopru && python3 -m pytest -q                         # 41 test
cd ../mobil && flutter test && ../scripts/uyum_testi.sh  # uyum testi artık ikili ses gönderiyor

# Elle: sahte STT her sese "yirmi metre yüksel" der
python3 -m mobile_bridge.deneme_sunucusu --token ABC --sahte-stt "yirmi metre yüksel"
python3 -m mobile_bridge.sahte_telefon --url $URL --wav kayit.wav   # 16 kHz mono WAV
```

WAV dosyası üretmek için: `arecord -f S16_LE -r 16000 -c 1 -d 3 kayit.wav`
(Linux) ya da Audacity → "16000 Hz, mono, 16-bit PCM" olarak dışa aktar.

**Kendin dene:**
1. `PcmParcalayici(parcaBoyu: 6400)` (200 ms) yap. Uyum testindeki gecikme nasıl değişti?
2. Ön kaydı kapat (`Ayarlar(onKayit: false)`). Telefonda tuşa basıp hemen konuş. İlk hece kayboluyor mu?

## Sonraki faz

**Faz 9:** Sahte STT yerine **gerçek Türkçe tanıma**: faster-whisper. Hangi
model, int8 mi float32 mi, ne kadar sürüyor (gerçek ölçümler). Bir de
konuşmaları ileride model eğitmek için kayıt olarak toplayacağız.
