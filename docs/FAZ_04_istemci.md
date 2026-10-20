# Faz 4 — Telefon istemcisi: bağlanmak, canlı kalmak, yeniden bağlanmak

> **Bu fazın sonunda:** Uygulama açılınca bir **bağlan ekranı** gelir. Adresi
> ve token'ı yazıp Faz 3'teki Python sunucusuna bağlanırsın. Başlıkta yeşil
> **OPERATÖR** rozeti ve ping süresi (ör. `12 ms`) görünür. Bağlantı koparsa
> uygulama kendiliğinden yeniden bağlanır. Adres telefonda saklanır; bir dahaki
> açılışta otomatik bağlanır.

## 1. Bu fazda eklenen dosyalar

```
lib/
├── baglanti/telsiz_istemcisi.dart   WebSocket istemcisi (ping, yeniden bağlanma)
├── durum/telsiz_kontrolcusu.dart    uygulamanın beyni (ChangeNotifier)
├── ayarlar/ayarlar.dart             adres/token'ı telefonda saklama
├── ekranlar/baglan_ekrani.dart      adres + token + "Bağlan"
└── app.dart                         hangi ekran gösterilecek?
test/
├── telsiz_istemcisi_test.dart       test içinde GERÇEK bir WebSocket sunucusu
├── telsiz_kontrolcusu_test.dart     sahte bağlantıyla kontrolcü
├── uyum_test.dart                   Dart istemcisi <-> Python köprüsü (gerçek)
└── sahteler.dart                    SahteBaglanti
scripts/uyum_testi.sh
```

## 2. Durum yönetimi: ChangeNotifier + ListenableBuilder

Uygulama büyüdükçe "hangi ekran neyi bilir?" sorusu karışır. Bizim kuralımız:

> **Ekranlar mantık içermez. Bütün durum `TelsizKontrolcusu`'ndadır.**

```
TelsizIstemcisi ──mesajlar──> TelsizKontrolcusu ──notifyListeners()──> ekranlar yeniden çizilir
      ^                         (durum: rol, bağlı mı, bildirim...)            │
      └──────────── kontrolcu.baglan(), kopar() <──── kullanıcı dokunur ───────┘
```

- `TelsizKontrolcusu extends ChangeNotifier`: Durum değişince `notifyListeners()` çağırır.
- Ekranlar `ListenableBuilder(listenable: k, builder: ...)` ile kontrolcüyü dinler; her bildirimde `builder` yeniden çalışır.

Ek bir paket gerekmez; Flutter'ın içinde var. (Provider, Riverpod, BLoC gibi
kütüphaneler aynı fikrin daha büyük uygulamalar için hazırlanmış halleridir.
Eski `feature_mobil` dalı BLoC kullanıyordu.)

## 3. Arayüz (interface) ve sahte nesneler

Kontrolcü somut `TelsizIstemcisi`'ni değil, bir **arayüzü** bilir:

```dart
abstract class TelsizBaglantisi {
  ValueListenable<BaglantiDurumu> get durum;
  Stream<Map<String, dynamic>> get mesajlar;
  Future<void> baglan(BaglantiAdresi adres, {required bool izleyici});
  void gonder(String tip, [Map<String, Object?> alanlar]);
  ...
}
```

Gerçek uygulamada `TelsizIstemcisi`, testte `SahteBaglanti` kullanılır
(`test/sahteler.dart`). Sahte bağlantıda `b.gelsin({...})` ile "sunucudan
mesaj gelmiş gibi" yaparsın; ağ, sunucu ve bekleme gerekmez. Python'daki
`RosArayuzu`'nün (Faz 3) Dart'taki karşılığı bu.

## 4. Dart'ta asenkron programlama: Future, Stream, Timer

| Kavram | Ne | Bizde |
|---|---|---|
| `Future<T>` | İleride **bir kez** gelecek sonuç | `await kanal.ready` (bağlantı açıldı mı?) |
| `Stream<T>` | Zamanla gelen **birçok** olay | `kanal.stream.listen(_gelen)` (sunucudan gelen her mesaj) |
| `StreamController` | Kendi stream'ini üretme | İstemci gelen mesajları `_mesajlar.add(m)` ile kontrolcüye yayınlar |
| `Timer.periodic` | Düzenli tekrar | 1 sn'de bir ping |
| `ValueNotifier<T>` | Tek bir değeri dinlenebilir kılar | bağlantı durumu |

Dart da Python'daki gibi tek thread'li bir olay döngüsünde çalışır; `await`
beklerken arayüz donmaz.

## 5. Bağlantının yaşam döngüsü

```
 kopuk ──baglan()──> baglaniyor ──hos_geldin──> bagli
   ^                     │  ^                     │
   │                hata │  └──yeniden (1,2,4,8 sn)┤ (kopma / 4 sn sessizlik)
   └───kopar()───────────┴────────────────────────┘
```

`telsiz_istemcisi.dart`'taki kurallar:

1. **Bağlı sayılmak için `hos_geldin` beklenir.** Soket açılması yetmez; token doğrulanmalı.
2. **Ping 1 sn'de bir:** `{"tip":"ping","t":<ms>}` gönderilir. `pong` içinde aynı `t` geri gelir. Şimdiki zamandan `t` çıkarılınca gidiş-dönüş süresi bulunur ve başlıkta görünür. Telefonla sunucunun saatlerinin eşit olması gerekmez; iki zaman da telefonun saatiyle ölçülür.
3. **Ölü bağlantı tespiti:** 4 sn boyunca hiçbir mesaj gelmezse bağlantı ölü sayılır. Wi-Fi'dan çıkınca TCP bağlantısı bazen dakikalarca "açık" görünür; uygulama bunu kendi zamanlayıcısıyla yakalar.
4. **Üstel geri çekilme (exponential backoff):** Yeniden bağlanma 1, 2, 4, 8, 8… sn aralıklarla denenir. Sunucu kapalıyken her 10 ms'de bir denemek telefonun pilini ve ağı boş yere yorar.
5. **Yanlış token'da vazgeç:** `yetkisiz` hatasında tekrar denemenin anlamı yok; `_istenen = false`.

## 6. Ayarları saklamak: shared_preferences

```dart
final p = await SharedPreferences.getInstance();
await p.setString('sunucuAdresi', a.sunucuAdresi);
```

Android'de `SharedPreferences`, iOS'ta `NSUserDefaults` kullanılır. Küçük
ayarlar için yeterlidir. **Not:** Token burada şifrelenmeden saklanıyor. Gerçek
bir ürün için `flutter_secure_storage` (Keychain/Keystore) daha doğru olur.

`main.dart`'taki `WidgetsFlutterBinding.ensureInitialized()` satırı, `runApp`'ten
önce bir eklenti (burada shared_preferences) kullanılacaksa zorunludur.

## 7. Üç seviye test

| Test | Ne doğrular | Hız |
|---|---|---|
| `telsiz_kontrolcusu_test.dart` | Kontrolcü mantığı (sahte bağlantı) | ms |
| `telsiz_istemcisi_test.dart` | İstemcinin gerçek bir WebSocket'le davranışı: merhaba, ping, yanlış token, sunucu susunca yeniden bağlanma. Sunucu test içinde `dart:io` ile açılıyor | ~1 sn |
| `uyum_test.dart` + `scripts/uyum_testi.sh` | Dart istemcisi ile **gerçek Python köprüsü** birlikte çalışıyor mu | ~2 sn |

Uyum testi iki ayrı ekibin (mobil ve yer istasyonu) protokolü aynı anlayıp
anlamadığını kanıtlar.

## 8. Dene

```bash
# Terminal 1
cd kopru && python3 -m mobile_bridge.deneme_sunucusu --token ABC
# Terminal 2
cd mobil && flutter test && ../scripts/uyum_testi.sh
flutter run      # telefonda: adres = bilgisayarın IP'si:8765, token = ABC
```

Telefon ve bilgisayar **aynı Wi-Fi'da** olmalı. Bilgisayarın IP'sini deneme
sunucusu yazdırır (`ws://192.168.x.y:8765/...`).

**Kendin dene:**
1. Uygulama bağlıyken deneme sunucusunu kapat (Ctrl+C). Başlık 4 sn içinde "BAĞLANTI KOPTU" olmalı. Sunucuyu tekrar aç; birkaç saniye içinde "OPERATÖR"e dönmeli.
2. Aynı token'la ikinci bir telefon ya da `sahte_telefon` bağla; uygulama izleyiciye düşerse bildirim şeridini gör.

## Sonraki faz

**Faz 5:** Bağlantı hazır, artık komut gönderiyoruz. Yazılan cümle yer
istasyonunda **drone reposunun gerçek command_parser'ından** geçecek ve geri
gelen **JSON komut** ekranda kart olarak görünecek. LLM ile ilişkinin kurulduğu
faz bu.
