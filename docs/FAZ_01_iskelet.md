# Faz 1 — Flutter iskeleti ve bas-konuş tuşu

> **Bu fazın sonunda:** Telefonda açılan, koyu temalı bir ekran; ortada büyük
> bir **BAS KONUŞ** tuşu, sağ üstte kırmızı **ACİL DUR**. Henüz hiçbir yere
> bağlanmıyor; tuşa ne kadar basılı tuttuğunu listeye yazıyor.

## 1. Neyi neden yapıyoruz?

Önce uygulamanın "kabuğunu" kuruyoruz: proje yapısı, tema ve en önemli iki
tuş. Bağlantı, ses ve yapay zekâ sonraki fazlarda bu kabuğun içine eklenecek.

Bu fazdaki asıl ders şu: **bas-konuş tuşu dokunduğun anda tepki vermeli.**
Telsizde tuşa basıp hemen konuşursun. Tuş geç tepki verirse ilk kelime kaybolur.

## 2. Flutter projesinin yapısı

`flutter create` komutu aşağıdaki klasörleri üretti:

```
mobil/
├── pubspec.yaml          # Projenin kimliği ve kullandığı paketler (Node'daki package.json gibi)
├── analysis_options.yaml # Kod kuralları (flutter analyze bunlara bakar)
├── lib/                  # BİZİM KODUMUZ — Dart dosyaları
│   ├── main.dart         # Program buradan başlar: runApp(...)
│   ├── app.dart          # MaterialApp: tema, başlangıç ekranı
│   ├── durum/            # Veri tipleri ve uygulama durumu
│   ├── bilesenler/       # Tekrar kullanılabilir küçük parçalar (widget)
│   └── ekranlar/         # Tam sayfalar
├── test/                 # Testler (flutter test)
├── android/              # Android'e özel ayarlar (izinler: AndroidManifest.xml)
└── ios/                  # iOS'a özel ayarlar (izinler: Runner/Info.plist)
```

`android/` ve `ios/` klasörlerine ancak izin eklerken dokunacağız (Faz 7).
Kodun neredeyse tamamı `lib/` altında.

## 3. Flutter'da her şey bir widget

Ekranda gördüğün her şey bir **widget**: yazı (`Text`), düğme (`FilledButton`),
yerleşim (`Column`, `Row`), boşluk (`Padding`). Widget'lar iç içe geçer ve bir
ağaç oluşturur:

```
MaterialApp
└── TelsizEkrani (Scaffold)
    ├── AppBar
    │   ├── Text('Drone Telsizi')
    │   └── AcilDurDugmesi
    └── Column
        ├── Expanded → liste
        └── PttDugmesi
```

Widget'lar iki çeşittir:

| Tür | Ne zaman | Örnek |
|---|---|---|
| `StatelessWidget` | Görüntü sadece dışarıdan gelen verilere bağlıysa | `AcilDurDugmesi`: sadece `onBasildi` alır |
| `StatefulWidget` | Widget'ın kendi değişen durumu varsa | `TelsizEkrani`: tuşa basılı mı, geçmiş listesi |

Stateful bir widget'ta durumu `setState(() { ... })` ile değiştirirsin.
Flutter bu çağrıdan sonra `build()` metodunu tekrar çalıştırır ve ekranı yeni
duruma göre yeniden çizer. `lib/ekranlar/telsiz_ekrani.dart` dosyasındaki
`_basildi` ve `_birakildi` metotları tam olarak bunu yapıyor.

## 4. Bu fazın en önemli dersi: `Listener` ve `onLongPress` farkı

`GestureDetector(onLongPressStart: ...)` ilk akla gelen yöntemdir. Ama
Flutter "uzun basma" olayını ancak parmak **yaklaşık 500 ms** basılı
kaldıktan sonra tetikler. Bu yöntemle "yirmi metre yüksel" dediğinde "yirmi"
kelimesi kaybolurdu. Eski `feature_mobil` dalında tuş bu şekildeydi.

Biz `Listener` kullanıyoruz (`lib/bilesenler/ptt_dugmesi.dart`):

```dart
Listener(
  onPointerDown: (_) => widget.basildi(),   // parmak ekrana değdiği AN
  onPointerUp: (_) => widget.birakildi(),   // parmak kalktığı AN
  onPointerCancel: (_) => widget.iptal(),   // sistem dokunmayı iptal ederse
  child: ...
)
```

`Listener` jest tanıma yapmaz, ham dokunma olaylarını gecikmesiz verir.
Bas-konuş için tam ihtiyacımız olan bu.

## 5. Tema: neden koyu ve yüksek kontrastlı?

Uygulama sahada, güneş altında kullanılacak. `app.dart` içindeki
`ColorScheme.fromSeed(seedColor: ..., brightness: Brightness.dark)` tek bir
renkten bütün paleti (birincil, ikincil, hata renkleri…) üretir. Material 3
bileşenleri bu paleti kendiliğinden kullanır. ACİL DUR ise paletten bağımsız,
sabit bir kırmızıdır (`0xFFD50000`): hangi temada olursan ol hemen fark
edilmeli.

## 6. Animasyon: nabız halkası

Dinlerken tuşun etrafında genişleyen bir halka görünür. Bunun için:

- `AnimationController` 0'dan 1'e giden bir sayı üretir (1,2 sn'de bir, tekrar eder).
- `AnimatedBuilder` bu sayı her değiştiğinde halkayı yeniden çizer: boyutu `1 + 0.5 × değer`, saydamlığı `1 − değer`.
- `SingleTickerProviderStateMixin` animasyonun ekran yenileme hızına (60/120 Hz) bağlanmasını sağlar.
- `dispose()` içinde controller kapatılır. Kapatılmazsa sayfa kapandıktan sonra da çalışmaya devam eder (bellek sızıntısı).

## 7. Test: widget testleri

`test/ekran_test.dart` uygulamayı gerçek bir telefon olmadan, sanal bir
ekranda çalıştırır:

```dart
final parmak = await tester.startGesture(tester.getCenter(find.text('BAS KONUŞ')));
await tester.pump();                       // bir kare çiz
expect(find.text('KONUŞ'), findsOneWidget); // basar basmaz değişti mi?
```

`pump()` sanal ekranda tek bir kare çizer. Test hiç beklemeden "KONUŞ"
yazısını buluyor; bu, tuşun gecikmesiz çalıştığının kanıtı.

## 8. Çalıştır ve dene

```bash
cd mobil
flutter pub get
flutter analyze
flutter test
flutter run          # telefon USB'de, geliştirici modu açık
```

**Kendin dene:**
1. `ptt_dugmesi.dart` dosyasında `Listener` yerine `GestureDetector(onLongPressStart: ..., onLongPressEnd: ...)` kullan. Telefonda gecikmeyi hisset. Test neden başarısız oldu?
2. `app.dart` içindeki `seedColor`'ı değiştir, hot reload (`r`) ile bütün renklerin değiştiğini gör.

## Sonraki faz

**Faz 2:** Telefon ile yer istasyonu nasıl konuşacak? Ortak bir **protokol**
tanımlayacağız: JSON mesajlar ve ses için ikili (binary) çerçeveler.
