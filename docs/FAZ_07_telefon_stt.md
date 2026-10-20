# Faz 7 — Bas-konuş: telefonun kendi Türkçe tanıyıcısı

> **Bu fazın sonunda:** Tuşa basılı tutup "yirmi metre yüksel" diyorsun.
> Konuşurken söylediğin ekranda canlı olarak beliriyor. Tuşu bırakınca
> telefonun tanıdığı **metin** yer istasyonuna gidiyor ve Faz 5'teki yoldan
> geçiyor: parser → JSON → kart. Mikrofon ve konuşma tanıma izinleri
> ekleniyor.

## 1. Konuşma tanıma (STT) nerede yapılmalı?

İki seçenek var. İkisini de yapacağız:

| | **Telefon STT** (bu faz) | **Yer STT** (Faz 8-9) |
|---|---|---|
| Kim yazıya çevirir? | Telefonun işletim sistemi (Android SpeechRecognizer / iOS SFSpeechRecognizer) | Yer istasyonu (faster-whisper) |
| Ağdan ne geçer? | Sadece metin (birkaç bayt) | Ham ses (~32 KB/sn) |
| Kurulum | Hazır, model indirmeye gerek yok | Bilgisayarda model gerekir |
| Doğruluk | Cihaza ve işletim sistemine bağlı; ölçmesi zor | Kontrol bizde, drone sözlüğü verilebilir, ölçülebilir |
| İnternet | Cihaza bağlı (bazıları buluta gönderir) | Gerekmez |

Telefon STT'si en hızlı başlangıç olduğu için önce onu yapıyoruz.

## 2. Platform eklentisi (plugin) nedir?

Flutter kodu (Dart) doğrudan mikrofona ya da işletim sisteminin tanıyıcısına
erişemez. **Eklentiler** bu işi yapar: Dart tarafında bir API sunarlar,
arkada Android'de Kotlin/Java, iOS'ta Swift kodu çalıştırırlar.

```
Dart: SpeechToText().listen(...)
   │  (platform kanalı - "method channel")
   ├── Android: android.speech.SpeechRecognizer
   └── iOS:     SFSpeechRecognizer
```

`flutter pub add speech_to_text` ile ekledik. Eklentiyi bir **arayüzün**
arkasına saklıyoruz (`lib/ses/cihaz_tanima.dart`):

```dart
abstract class CihazTanima {
  Future<bool> hazirla();
  Future<void> basla({required String dil, required bool cevrimdisi, void Function(String)? kismi});
  Future<TanimaSonucu?> bitir({Duration bekle});
  Future<void> iptal();
}
class SistemTanima implements CihazTanima { ... speech_to_text ... }   // gerçek telefon
class SahteTanima implements CihazTanima { ... }                         // testler
```

Faydası: testler gerçek bir mikrofon olmadan çalışır. Yarın başka bir
tanıyıcıya (ör. telefonda Whisper) geçmek istersen sadece bir sınıf eklersin.

## 3. speech_to_text ayarları neden böyle?

```dart
SpeechListenOptions(
  localeId: 'tr_TR',
  partialResults: true,                     // konuşurken ara sonuç -> ekranda canlı metin
  listenMode: ListenMode.dictation,          // serbest konuşma (komut listesi değil)
  pauseFor: const Duration(seconds: 15),     // !!! bitişi TUŞ belirler
  listenFor: const Duration(seconds: 20),
  onDevice: cevrimdisi,                      // internetsiz tanıma iste
  contextualPhrases: droneSozlugu,           // "yüksel, alçal, metre, kuzeye..." ipucu
)
```

- **`pauseFor` uzun:** Varsayılan davranışta tanıyıcı ~3 sn sessizlik görünce kendiliğinden durur. Bas-konuşta bitişi kullanıcı belirler. Eski `feature_mobil` dalında `pauseFor: 3 sn` vardı; "yirmi metre... (düşünür) ...yüksel" derken kesiliyordu.
- **`contextualPhrases`:** Tanıyıcıya "bu kelimeler sık geçecek" ipucu verir. Faz 9'daki Whisper'ın `initial_prompt` ayarının karşılığı. "yüksel"in "yüksek", "alçal"ın "al çal" diye duyulma ihtimalini azaltır (destekleyen platformlarda).
- **`onDevice`:** Türkçe internetsiz tanıma her cihazda yok. Ayar açıkken cihaz desteklemiyorsa hata verir. Bu yüzden varsayılanı kapalı.

### Tuş bırakıldığında son sonucu beklemek

Tuşu bıraktığında tanıyıcının **son** (final) sonucu birkaç yüz ms sonra gelir.
`bitir()` bunu bir **Completer** ile bekler:

```dart
await _stt.stop();
await _final.future.timeout(bekle, onTimeout: () {});   // en fazla 1.5 sn
```

`Completer`, elle tamamlanan bir `Future`'dır: `onResult` geri çağırımı
`finalResult == true` görünce `_final.complete()` der, bekleyen `await`
devam eder. Geri çağırım (callback) tabanlı bir API'yi `async/await`'e
çevirmenin standart yolu budur.

## 4. Kontrolcüdeki akış

```
pttBasla()  ─ titreşim, kart (giris: 'ses'), ptt = dinliyor
            └ tanima.basla(..., kismi: (m) => kismiMetin = m)   -> ekranda "20 metre"
pttBirak()  ─ < 250 ms basıldıysa iptal (cebe sürtünme)
            ├ ptt = isleniyor
            ├ sonuc = await tanima.bitir()
            └ gonder('metin', {id, metin, kaynak: 'telefon_stt', guven})
                        └──> Faz 5 yolu: köprü -> parser -> JSON -> kart
```

Dikkat: Telefonda tanınan metin, yazılı komutla **aynı** `metin` mesajıyla
gider. Tek fark `kaynak: 'telefon_stt'` alanı. Kart bunu "telefon STT" diye
gösterir. Yer istasyonu için ikisi de sadece bir cümle; normalize, hızlı yol,
LLM ve güvenlik aynen uygulanır.

Kenar durumları:
- **Hiçbir şey duyulmadı:** Kart `ANLAŞILMADI` ("ses duyulmadı"), sunucuya bir şey gitmez.
- **Konuşurken bağlantı koptu:** `pttIptal()`; yarım cümle gitmez.
- **İzleyici:** `komutVerebilir` false olduğu için tuş pasif.

## 5. İzinler: Android ve iOS

Mikrofon "tehlikeli" izin sınıfında. Hem dosyada **beyan** edilmeli hem de
çalışma anında kullanıcıdan **istenmeli** (ilk kullanımda eklenti sorar).

**Android** — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<application android:usesCleartextTraffic="true" ...>
<queries>
  <intent><action android:name="android.speech.RecognitionService" /></intent>
</queries>
```

- `INTERNET`: Faz 4'ten beri WebSocket kullanıyoruz ama bu izin yoktu! `flutter run` (debug) bu izni kendiliğinden ekler; **release** APK eklemez. Uygulama yayında hiç bağlanamazdı. Klasik bir "bende çalışıyordu" hatası.
- `usesCleartextTraffic`: Android 9+ şifresiz (`ws://`) trafiği varsayılan olarak engeller. Yerel ağda izin veriyoruz; ortak bir ağda `wss://` (TLS) kullanılmalı.
- `<queries>`: Android 11+ "paket görünürlüğü". Uygulama, telefondaki konuşma tanıma servisini ancak bunu açıkça belirtirse görebilir. Yoksa `initialize()` "tanıma yok" der.

**iOS** — `ios/Runner/Info.plist`:

| Anahtar | Neden |
|---|---|
| `NSMicrophoneUsageDescription` | Mikrofon izni penceresinde kullanıcıya gösterilen açıklama. **Yoksa uygulama çöker.** |
| `NSSpeechRecognitionUsageDescription` | Konuşma tanıma izni (iOS ayrıca sorar) |
| `NSLocalNetworkUsageDescription` | iOS 14+ yerel ağdaki cihazlara erişim izni |
| `NSAppTransportSecurity > NSAllowsLocalNetworking` | Yerel ağda şifresiz bağlantıya izin |

## 6. Ekran

- Bas-konuş tuşu artık kontrolcüye bağlı: `basildi: k.pttBasla`, `birakildi: k.pttBirak`.
- Konuşurken tuşun üstünde ara sonuç görünür: `"20 metre"` → `"20 metre yüksel"`. Kullanıcı yanlış duyulduğunu tuşu bırakmadan görür.

## 7. Dene

```bash
cd mobil && flutter test && ../scripts/uyum_testi.sh
flutter run        # gerçek telefonda: ilk basışta mikrofon izni sorulur
```

Gerçek cihazda dikkat edilecekler:
- Android'de "Google" uygulaması / konuşma servisleri kurulu ve Türkçe dil paketi indirilmiş olmalı.
- iOS'ta Ayarlar → Genel → Klavye → Dikte açık olmalı.

**Kendin dene:**
1. `pauseFor`'u 2 saniyeye indir. Tuşa basılı tutup "yirmi metre" de, 3 sn bekle, "yüksel" de. Ne oldu?
2. Ayarlarda "internetsiz tanıma"yı aç (`cevrimdisiTanima`, Faz 10'da ayar ekranına gelecek). Telefonun uçak modunda çalışıp çalışmadığına bak.

## Sonraki faz

**Faz 8:** Ses telefonda yazıya çevrilmeyecek; ham ses yer istasyonuna
**akıtılacak**. Dijital ses (16 kHz, PCM16), 20 ms parçalar, ön kayıt için halka
tampon ve ikili WebSocket çerçeveleri.
