# Faz 2 — Protokol: telefon ile yer istasyonu nasıl konuşur?

> **Bu fazın sonunda:** İki tarafta (Dart ve Python) aynı kuralları uygulayan
> bir mesaj protokolü ve aynı test vektörüyle doğrulanmış ikili ses çerçevesi.
> Ekranda yeni bir şey yok; bu faz "altyapı".

## 1. Neden önce protokol?

Telefon (Dart) ve yer istasyonu (Python) iki farklı dilde yazılıyor. Birbirlerini
anlamaları için **ortak bir dil** gerekiyor: hangi mesaj var, alanları ne, sayılar
hangi bayt sırasıyla yazılıyor? Bunu kodlamaya başlamadan önce yazıya dökersen,
iki tarafı ayrı ayrı geliştirip ayrı ayrı test edebilirsin.

## 2. Tek bağlantı, iki çeşit çerçeve

Bağlantı tek bir **WebSocket** (Faz 3-4'te ayrıntısıyla). WebSocket iki çeşit
mesaj (çerçeve) taşır:

| Çerçeve | Ne taşıyoruz | Neden |
|---|---|---|
| **Metin** (JSON) | kontrol mesajları: `merhaba`, `metin`, `acil_dur`, `komut`… | Okunur, hata ayıklaması kolay, her dilde hazır kütüphanesi var |
| **İkili** (binary) | ses parçaları | Ses ham bayt; JSON'a koymak için base64'e çevirmek gerekir, bu da veriyi %33 büyütür ve işlemciyi yorar |

Her JSON mesajında bir `"tip"` alanı vardır. Alıcı önce tipe bakar, sonra
mesajı ona göre işler:

```json
{"tip":"metin","id":42,"metin":"20 metre yüksel"}
```

Mesaj listesinin tamamı `kopru/mobile_bridge/protokol.py` içindeki
`GELEN_TIPLER`'de. Her fazda bu mesajlardan bazılarını kullanmaya başlayacağız:

| Mesaj (telefon → istasyon) | Faz | Anlamı |
|---|---|---|
| `merhaba {token, rol}` | 3 | Kimlik doğrula, operatör ya da izleyici ol |
| `ping {t}` | 4 | Bağlantı canlı mı? Gidiş-dönüş süresi |
| `metin {id, metin}` | 5 | Yazıyla ya da telefonda tanınmış komut |
| `acil_dur` | 6 | Drone'u hemen durdur |
| `ptt_basla / ptt_bitti / ptt_iptal {id}` | 8 | Bas-konuş ses akışının başı ve sonu |

## 3. İkili ses çerçevesi: başlık + PCM

```
 0        4        8                     8+N
 ┌────────┬────────┬──────────────────────┐
 │  id    │  sıra  │  PCM16 ses (N bayt)  │
 │ uint32 │ uint32 │  16 kHz, mono        │
 └────────┴────────┴──────────────────────┘
```

- **id**: Hangi konuşmaya ait? (Her bas-konuşta yeni bir id.)
- **sıra**: Kaçıncı parça? Parçalar sırasız gelse bile istasyon sıraya dizebilir (Faz 8).
- **PCM**: Ham ses örnekleri (Faz 8'de ayrıntısıyla).

### Bayt sırası (endianness)

`0x01020304` sayısı 4 bayttır: `01 02 03 04`. Bunu belleğe iki şekilde yazabilirsin:

| | 1. bayt | 2. | 3. | 4. |
|---|---|---|---|---|
| big-endian (en büyük önce) | 01 | 02 | 03 | 04 |
| **little-endian** (en küçük önce) | **04** | **03** | **02** | **01** |

İki taraf aynı sırayı kullanmazsa id `0x01020304` yerine `0x04030201` okunur ve
konuşmalar karışır. Biz **little-endian** seçtik; telefon ve bilgisayar
işlemcilerinin hepsi zaten bu sırayla çalışıyor.

**Dart** (`lib/protokol/mesajlar.dart`):
```dart
final cerceve = Uint8List(8 + pcm.length);     // ham bayt dizisi
ByteData.sublistView(cerceve)                   // üzerine "sayı yazma" görünümü
  ..setUint32(0, konusmaId, Endian.little)
  ..setUint32(4, sira, Endian.little);
cerceve.setRange(8, cerceve.length, pcm);
```

**Python** (`kopru/mobile_bridge/protokol.py`):
```python
SES_BASLIGI = struct.Struct('<II')   # '<' = little-endian, 'I' = uint32
SES_BASLIGI.pack(konusma_id, sira) + pcm
```

### Ortak test vektörü

İki tarafın gerçekten aynı baytları ürettiğini nasıl bilirsin? Aynı girdiyle iki
tarafta da test yaz:

```
id = 0x01020304, sıra = 7, PCM = [9, 8]
beklenen = [4, 3, 2, 1, 7, 0, 0, 0, 9, 8]
```

- `mobil/test/protokol_test.dart` → `ORTAK TEST VEKTÖRÜ`
- `kopru/test/test_protokol.py` → `test_ortak_test_vektoru`

Biri değişip diğeri değişmezse testlerden biri kırılır.

## 4. Gelen mesajı doğrulamak

Ağdan gelen hiçbir veriye güvenme. `protokol.json_coz()` şunları kontrol eder:

- Geçerli JSON mu? Bir nesne (`{...}`) mi?
- `tip` biliniyor mu?
- Zorunlu alanlar var mı ve tipleri doğru mu? Örneğin `"id": "7"` (metin) reddedilir. `"id": true` da reddedilir; Python'da `bool`, `int`'in alt sınıfı olduğu için bu ayrıca kontrol edilir.

Hata olursa `ProtokolHatasi(kod, mesaj)` fırlatılır; `kod` telefona geri
gönderilir (`{"tip":"hata","kod":"eksik_alan",...}`).

Dart tarafında `jsonCoz()` geçersiz veride `null` döndürür. Telefon bilinmeyen
bir mesajı görmezden gelir, çökmez.

## 5. Bağlantı adresi ve QR kod

Yer istasyonu açılınca şöyle bir adres üretecek (Faz 10'da QR olarak):

```
ws://192.168.1.20:8765/telsiz?token=Xy7...
```

`BaglantiAdresi.coz()` kullanıcının yazabileceği her biçimi kabul eder:

| Girdi | Sonuç |
|---|---|
| `ws://192.168.1.20:8765/telsiz?token=ABC` | adres + token |
| `192.168.1.20:8765` | `ws://` ve `/telsiz` eklenir, token ayrıca girilir |
| `192.168.1.20` | port 8765 varsayılır |
| `http://...` | **geçersiz** (WebSocket değil) |

Dart'ın `Uri` sınıfı adresi parçalarına ayırır (`scheme`, `host`, `port`, `path`,
`queryParameters`). Elle `split(':')` yapmaktan çok daha güvenli.

## 6. Dart dersleri

- **`Uint8List` / `ByteData`**: Ham bayt dizisi ve onun üzerinde sayı okuma/yazma görünümü. Kopyalama yapmadan aynı belleğe farklı açılardan bakarsın.
- **Kademeli çağrı (cascade) `..`**: `x..a()..b()` → `x.a(); x.b();` ve sonuç yine `x`.
- **`static` fabrika metodu**: `BaglantiAdresi.coz()` nesne üretir ya da `null` döndürür. Hata fırlatmak yerine "olmadı" demenin Dart'taki temiz yolu.
- **`==` ve `hashCode`**: İki adres nesnesinin "aynı" sayılması için ikisi birlikte tanımlanır.

## 7. Çalıştır

```bash
cd mobil && flutter test test/protokol_test.dart
cd kopru && python3 -m pytest -q
```

**Kendin dene:** Python'da `'<II'` yerine `'>II'` (big-endian) yaz. Ortak test
vektörü testinin kırıldığını gör.

## Sonraki faz

**Faz 3:** Yer istasyonu tarafında bu protokolü konuşan bir **WebSocket
sunucusu** yazacağız (Python, asyncio) ve telefon olmadan deneyebilmek için
komut satırından çalışan bir **sahte telefon**.
