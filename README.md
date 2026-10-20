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
- Yer istasyonu için (Faz 3'ten itibaren): Python 3.10+, `pip install websockets`
