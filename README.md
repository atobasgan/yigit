# Yiğit — Drone Telsizi (mobil)

Telefonu bir **telsiz** gibi kullanarak drone'a Türkçe sesli komut veren
uygulama: **bas, konuş, bırak**. Komutu anlama işi telefonda değil, yer
istasyonunda yapılır (drone reposu: normalize → hızlı yol / LLM → güvenlik →
PX4). Telefon sonucu ekranda kart olarak gösterir ve sesli cevap verir.

Bu repo **öğrenmek için fazlara bölündü**. Her faz çalışan bir ara sürümdür ve
kendi açıklama dökümanıyla gelir. Kodu baştan sona okumak yerine fazları sırayla
izle.

## Fazlar

| Faz | Konu | Öğrenilenler | Döküman |
|---|---|---|---|
| 1 | Flutter iskeleti, bas-konuş tuşu | widget, state, tema, `Listener`, animasyon, widget testi | [FAZ_01](docs/FAZ_01_iskelet.md) |
| 2 | Protokol (Dart + Python) | JSON vs ikili çerçeve, bayt sırası, doğrulama, ortak test vektörü | [FAZ_02](docs/FAZ_02_protokol.md) |
| 3 | Yer istasyonu köprüsü (Python) | asyncio, WebSocket sunucusu, çekirdek/kabuk ayrımı, token, roller | [FAZ_03](docs/FAZ_03_kopru_sunucusu.md) |
| 4 | Telefon istemcisi, bağlan ekranı | ChangeNotifier, arayüz + sahte nesne, Future/Stream/Timer, ping, yeniden bağlanma, uyum testi | [FAZ_04](docs/FAZ_04_istemci.md) |
| 5 | Yazılı komut → JSON → kart | telefon yorumlamaz, JSON şeması, hızlı yol vs LLM, eşleştirme kuyruğu, gerçek parser | [FAZ_05](docs/FAZ_05_komut_ve_json.md) |
| 6 | Güvenlik | ACİL DUR, izleyici, kalp atışı, telsiz koparsa dur, yarış durumu ve nesil sayacı, titreşim | [FAZ_06](docs/FAZ_06_guvenlik.md) |
| 7 | Bas-konuş: telefon STT | platform eklentisi, speech_to_text, Completer, ara sonuç, Android/iOS izinleri | [FAZ_07](docs/FAZ_07_telefon_stt.md) |
| 8 | Ham ses akışı | dijital ses (16 kHz PCM16), bant hesabı, 20 ms parçalar, halka tampon/ön kayıt, ikili çerçeveler, iki STT modu | [FAZ_08](docs/FAZ_08_ham_ses.md) |
| 9 | Yer STT: faster-whisper + veri toplama | Whisper modelleri, int8 nicemleme, initial_prompt, gerçek ölçümler, ısınma, thread, WAV + etiketler.csv | [FAZ_09](docs/FAZ_09_yer_stt.md) |

*(Tablo her fazda büyüyecek.)*

## Bir faza dönmek

Her fazın son hali ayrı bir dalda durur (`faz-01`, `faz-02`, …); `main` en son hal:

```bash
git checkout faz-01           # o fazdaki koda dön
git checkout main             # son hale dön
git diff faz-01 faz-02        # iki faz arasında neler değişti?
git log --oneline             # her commit bir faz
```

## Klasörler

```
mobil/   Flutter uygulaması (telefon)
kopru/   Python: yer istasyonu köprüsü (telefon <-> ROS 2)
docs/    her fazın öğretici açıklaması
```

## Gerekenler

- Flutter SDK 3.47+ (`flutter doctor`)
- Telefonda deneme için Android Studio (Android SDK) ya da Xcode
- Yer istasyonu için (Faz 3'ten itibaren): Python 3.10+, `pip install -r kopru/requirements.txt`
- Faz 5'ten itibaren drone reposu (komutu anlayan `command_parser`): `export DRONE_REPO=~/drone`
  (varsayılan: bu reponun yanındaki `../drone`)
