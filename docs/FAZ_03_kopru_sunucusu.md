# Faz 3 — Yer istasyonu köprüsü: WebSocket sunucusu (Python)

> **Bu fazın sonunda:** Bilgisayarda çalışan bir telsiz sunucusu. Token ile giriş
> var, tek operatör ve izleyiciler var. Gelen metni ROS'a gidecekmiş gibi
> ekrana yazıyor. Telefon olmadan denemek için de komut satırından çalışan bir
> `sahte_telefon` var.

## 1. Köprü ne işe yarar?

Telefon ROS 2 bilmez; ROS 2 de WebSocket bilmez. Köprü ikisinin arasında çevirmenlik yapar:

```
Telefon  ──WebSocket (Faz 2 protokolü)──>  KÖPRÜ  ──ROS 2 topic'leri──>  drone sistemi
                                        (bu faz)    /voice/text, /drone/emergency_stop...
```

Bu fazda "ROS 2 tarafı" henüz sahte: metin ekrana yazılıyor. Gerçek ROS 2
node'u Faz 10'da gelecek. Ama telefonun konuştuğu her şey şimdiden gerçek.

## 2. Mimari: "çekirdek" ve "kabuk" ayrımı

```
kopru/mobile_bridge/
├── protokol.py        Faz 2: mesaj kuralları
├── cekirdek.py        BEYİN: kim bağlı, kim operatör, mesaja ne cevap verilir
├── sunucu.py          KABUK: ağ (asyncio + websockets), mesajları çekirdeğe taşır
├── sahte_telefon.py   test istemcisi
└── deneme_sunucusu.py çalıştırılabilir program (ROS'suz)
```

En önemli tasarım kararı şu: **çekirdek ağ açmaz, ROS bilmez, saati
dışarıdan alır.** Her olay bir metot çağrısı, her cevap da bir dönüş değeri:

```python
cikti = cekirdek.metin_cercevesi(istemci, '{"tip":"metin","id":7,"metin":"kalk"}')
# cikti == [(HERKES, '{"tip":"duyuldu","id":7,"metin":"kalk",...}')]
```

Bunun faydaları:

- **Test kolaylığı:** `test/test_cekirdek.py` ağ açmadan, milisaniyeler içinde çalışır. Saat bile sahte (`Saat` sınıfı); Faz 6'da "3 saniye sinyal gelmezse" kuralını beklemeden test edeceğiz.
- **Tek sorumluluk:** Ağ hataları `sunucu.py`'de, iş kuralları `cekirdek.py`'de kalır.
- **ROS'tan bağımsızlık:** Çekirdek ROS işlerini `RosArayuzu` üzerinden ister (`metin_yayinla`). Testte sahtesi, deneme sunucusunda `YankiRos`, Faz 10'da gerçek ROS node'u bu arayüzü uygular. Bu kalıbın adı **bağımlılık tersine çevirme** (dependency inversion).

## 3. asyncio ve WebSocket

`sunucu.py` Python'un **asyncio** kütüphanesini kullanır. Bir telsiz sunucusu
aynı anda birkaç telefonu dinler; her biri için ayrı bir thread açmak yerine
tek bir **olay döngüsü** bütün bağlantıları sırayla, beklemeden işler:

```python
async def _baglanti(self, ws):            # her yeni telefon için bir "coroutine"
    istemci = self.cekirdek.baglandi(adres)
    async for veri in ws:                 # mesaj gelene kadar BEKLER, ama döngüyü kilitlemez
        cikti = self.cekirdek.metin_cercevesi(istemci, veri)
        await self._gonder(cikti)
```

`await` şu anlama gelir: "burada beklemem gerekiyor, bu arada diğer işlere bak."
Bir telefon mesaj göndermezken diğerleri cevapsız kalmaz.

Önemli ayarlar (`websockets.serve(...)`):

| Ayar | Değer | Neden |
|---|---|---|
| `compression=None` | sıkıştırma kapalı | Ses zaten sıkıştırılamaz; sıkıştırma gecikme ekler |
| `max_size=1 MB` | tek çerçeve sınırı | Kötü niyetli dev bir mesaj belleği doldurmasın |
| `ping_interval=5` | 5 sn'de bir TCP seviyesi ping | Ölü bağlantıları ağ katmanında fark et |

**Thread uyarısı:** Çekirdeğe yalnızca olay döngüsünün kendi thread'i
dokunur. Başka bir thread'den gelen olaylar (Faz 9'da STT, Faz 10'da ROS)
`sunucu.disaridan(...)` ile döngüye aktarılır (`call_soon_threadsafe`). Bu
sayede kilit (lock) kullanmamız gerekmiyor.

## 4. Giriş: token ve roller

İlk mesaj her zaman `merhaba` olmalı:

```json
{"tip":"merhaba","surum":1,"token":"ABC","rol":"operator","cihaz":"Pixel 8"}
```

- **Token:** Aynı Wi-Fi'daki herkes drone'a komut veremesin. Token, sunucunun açılışta ürettiği ya da `TELSIZ_TOKEN` ortam değişkeninden aldığı gizli bir metin (Faz 10'da QR koda yazılacak). Token'lar `==` ile değil `hmac.compare_digest` ile karşılaştırılır. `==` ilk farklı harfte durur; ölçülen süre, saldırgana token'ın kaç harfini doğru bildiğini ele verebilir (zamanlama saldırısı). `compare_digest` her zaman aynı sürede çalışır.
- **Sürüm:** Protokol ileride değişirse eski uygulama "anlamadığı" mesajlarla çalışmaya çalışmasın diye kontrol edilir.
- **Tek operatör:** Aynı anda yalnızca bir telefon komut verebilir; diğerleri **izleyici** olur. İki kişinin aynı anda "sağa dön" ve "sola dön" demesi tehlikelidir. Operatör ayrılınca yer boşalır.

Cevaplar:

```json
{"tip":"hos_geldin","surum":1,"rol":"operator","yer_stt":false,...}
{"tip":"hata","kod":"yetkisiz","mesaj":"token hatalı"}
{"tip":"hata","kod":"operator_dolu","mesaj":"başka bir operatör bağlı; izleyici olarak bağlandın"}
```

## 5. İlk komut: `metin` → `duyuldu`

```
telefon:   {"tip":"metin","id":7,"metin":"20 metre yüksel"}
köprü:     ros.metin_yayinla("20 metre yüksel")      (ileride /voice/text)
köprü ->   HERKES: {"tip":"duyuldu","id":7,"metin":"20 metre yüksel","kaynak":"klavye"}
```

`duyuldu` yalnızca gönderene değil **herkese** gider: izleyiciler de
operatörün ne söylediğini görür. `id` alanı telefonun hangi konuşmanın
cevabını aldığını bilmesini sağlar (Faz 5'te ekrandaki kartlar bununla eşleşir).

## 6. Dene

```bash
cd kopru
pip install -r requirements.txt
python3 -m pytest -q                      # 22 test

# Terminal 1:
python3 -m mobile_bridge.deneme_sunucusu --token ABC
# Terminal 2:
python3 -m mobile_bridge.sahte_telefon --url 'ws://127.0.0.1:8765/telsiz?token=ABC' \
    --metin "20 metre yüksel"
```

Gerçek çıktı:

```
<- {'tip': 'hos_geldin', 'surum': 1, 'rol': 'operator', 'yer_stt': False, ...}
<- +     1 ms {"tip": "duyuldu", "id": 2151, "metin": "20 metre yüksel", "kaynak": "klavye", "stt_ms": null}
```

Sunucu tarafında `/voice/text <- "20 metre yüksel"` yazar. Yanlış token
denersen `{'tip': 'hata', 'kod': 'yetkisiz', ...}` alırsın.

**Kendin dene:**
1. İki terminalden aynı anda iki `sahte_telefon` bağla (birine `--bekle 10` ver). İkincisi `operator_dolu` hatası almalı.
2. `cekirdek.py`'de `compare_digest` yerine `==` kullan. Testler yine geçer; güvenlik açığı testle yakalanmayabilir, bu yüzden kod incelemesi de önemli.

## Sonraki faz

**Faz 4:** Telefon tarafında bu sunucuya bağlanan WebSocket **istemcisi**:
ping ile canlılık kontrolü, bağlantı koparsa kendiliğinden yeniden bağlanma ve
bir bağlan ekranı.
