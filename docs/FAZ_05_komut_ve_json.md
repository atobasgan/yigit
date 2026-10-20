# Faz 5 — Yazılı komut → JSON → kart (LLM ile bağlantı)

> **Bu fazın sonunda:** Telefona "önce 20 metre yüksel sonra kuzeye 50 metre
> git" yazıyorsun. Cümle yer istasyonunda drone reposunun **gerçek**
> `command_parser`'ından geçiyor: normalize, hızlı yol ve gerekirse LLM.
> Üretilen **JSON komut** telefona dönüyor ve bir kartta görünüyor. Komut
> güvenlik katmanından geçip sanal bir drone'da "yürütülüyor".

## 1. En önemli kural: telefon komutu YORUMLAMAZ

```
Telefon:  "20 metre yüksel" yazıldı ──metin──>  Yer istasyonu: ANLAMA burada
Telefon:  kartı göster          <──JSON────    (normalize, hızlı yol, LLM, güvenlik)
```

Eski `feature_mobil` dalında telefon kendi regex'leriyle komut üretiyordu
("ileri" = 0.5 m/s, sonsuza kadar). Bunun iki büyük sorunu vardı:

1. **İki ayrı beyin:** Telefondaki kurallar ile drone reposundaki `fast_path.py` birbirinden habersizdi. Birinde düzeltilen hata diğerinde kalırdı.
2. **Güvenlik atlanıyordu:** Telefon doğrudan hız komutu gönderdiği için irtifa, mesafe ve geofence limitlerinin hiçbiri çalışmıyordu.

Bu yüzden **hızlı tuşlar da** ("kalk", "eve dön") komut değil, **metin**
olarak gider. Telefonun tek "kendi kararı" Faz 6'daki ACİL DUR olacak.

## 2. Bir komutun yolculuğu (gerçek çıktılarla)

```
[1] Telefon -> köprü           {"tip":"metin","id":42,"metin":"yirmi metre yüksel","kaynak":"klavye"}
[2] Köprü -> HERKES            {"tip":"duyuldu","id":42,"metin":"yirmi metre yüksel",...}
[3] Köprü -> parser            /voice/text  "yirmi metre yüksel"
[4] command_parser             normalize   : "20 m yüksel"         (yazıyla sayı -> rakam)
                               acil kelime : yok
                               hızlı yol   : eşleşti (regex, ~0.2 ms)
                               JSON        : {"adimlar":[{"komut":"yuksel","metre":20}]}
[5] Köprü -> HERKES            {"tip":"komut","id":42,"kaynak":"hizli_yol","metin":"20 m yüksel",
                                "adimlar":[{"komut":"yuksel","metre":20.0}],"gecikme_ms":1}
[6] Güvenlik + yürütme         irtifa sınırı, mesafe, geofence, batarya  ✓
[7] Köprü -> HERKES            {"tip":"geri_bildirim","id":42,"durum":"yurutuyor","mesaj":"20 metre yükseliyorum"}
                               {"tip":"geri_bildirim","id":42,"durum":"tamamlandi",...}
```

Telefondaki kart bu mesajlarla adım adım dolar:

```
┌───────────────────────────────────────────────┐
│ ⌨  20 m yüksel                     [YÜRÜTÜYOR] │
│ duyulan    "yirmi metre yüksel"         klavye │
│ normalize  20 m yüksel                         │
│ [HIZLI YOL]                              14 ms │
│ { "adimlar": [ { "komut": "yuksel",            │
│                  "metre": 20.0 } ] }           │
│ • 20 metre yükseliyorum                        │
└───────────────────────────────────────────────┘
```

## 3. JSON şeması: LLM ile drone arasındaki sözleşme

Hızlı yol da LLM de **aynı** JSON biçimini üretir (drone reposu:
`command_parser/schema.py`, MIMARI.txt Bölüm 4):

```json
{"adimlar": [
  {"komut": "yuksel", "metre": 20},
  {"komut": "git_yon", "yon": "kuzey", "metre": 50}
]}
```

| komut | parametreler | örnek cümle |
|---|---|---|
| `kalk` | `irtifa_m?` | "kalk", "on metreye kalk" |
| `yuksel` / `alcal` | `metre` (göreli) | "20 metre yüksel" |
| `irtifaya_cik` | `metre` (mutlak) | "100 metreye çık" |
| `git_yon` | `yon`, `metre` | "kuzeye 50 metre git" |
| `don` | `yon` (sag/sol), `derece` | "sağa 90 derece dön" |
| `bekle` / `hiz_ayarla` | `saniye` / `mps` | "5 saniye bekle" |
| `in`, `eve_don`, `dur` | — | "in", "eve dön" |
| `bilinmiyor` | — | "bugün hava nasıl" |

### Hızlı yol mu, LLM mi?

| | Hızlı yol | LLM |
|---|---|---|
| Ne | Kesin regex kalıpları | Küçük dil modeli (Qwen3 0.6B / 1.7B, llama-server) |
| Ne zaman | Basit, tek komut: "20 metre yüksel", "kalk" | Serbest / çok adımlı: "önce ... sonra ...", "biraz yükselsene" |
| Süre | ~0.2 ms | CPU'da 1–3 sn, GPU'da 50–200 ms |
| Kart rozeti | `HIZLI YOL` | `LLM` |

LLM'e cümle gönderilirken JSON şeması **kısıt olarak** verilir
(`response_format: json_schema`). Model şemaya uymayan bir token üretemez;
çıktı her zaman geçerli JSON olur. Gerçek bir LLM çıktısı:

```
"Önce 20 metre yüksel, sonra kuzeye 50 metre git."
  -> {"adimlar":[{"komut":"yuksel","metre":20.0},{"komut":"git_yon","yon":"kuzey","metre":50.0}]}
  kaynak: llm
```

### İleride LLM değişirse?

Telefon hiçbir şeyden etkilenmez. Faz 4'teki fine-tune'lu model geldiğinde
ya da LLM bir API'den verildiğinde (drone reposu: `LLM_API_SENARYOSU.txt`)
değişen tek şey `command_parser/llm_client.py` olur. Telefon yine aynı JSON'u
alır; sadece kartlardaki gecikme kısalır ve `LLM` rozetli kartlar artar ya da
azalır.

## 4. Köprü: hangi sonuç hangi kartın?

Sorun şu: köprü metni ROS'a `/voice/text` olarak yayınlıyor ve bu sade bir
metin (String). Kartın `id`'si ROS'tan geçemiyor. Parser'dan sonuç geldiğinde
bunun hangi kartın cevabı olduğunu nasıl bileceğiz?

Çözüm (`cekirdek.py`): parser cümleleri **sırayla** işler. Köprü de
yayınladığı konuşmaları sırayla bir kuyrukta tutar:

```python
self._bekleyen.append(_Bekleyen(konusma_id, self.saat()))   # metni yayınlarken
...
bekleyen = self._bekleyen.popleft()                         # sonuç gelince: en eskisi
```

15 sn'den eski bekleyenler atılır. Yürütücünün geri bildirimleri
("yükseliyorum", "tamamlandı") ise **son komutun** kartına bağlanır.

## 5. Deneme sunucusu artık gerçek parser kullanıyor

`kopru/mobile_bridge/deneme_sunucusu.py`, drone reposundaki paketleri
`drone_yolu.py` ile bulur:

```bash
export DRONE_REPO=~/drone       # varsayılan: bu reponun yanındaki ../drone
```

`SanalDrone` sınıfı ROS'un yerini alır:

1. Metni `KomutCozucu.coz()`'a verir. Bu, drone reposunun gerçek normalize + hızlı yol + LLM hattıdır.
2. Çıkan JSON'u telefona `komut` olarak gönderir.
3. Komut listesini drone reposunun **gerçek güvenlik katmanından** (`Guvenlik.liste_kontrol_et`) geçirir.
4. Geçerse sanal drone'un konumunu adım adım günceller, `yurutuyor/tamamlandi` gönderir.

**Önemli:** Parser (özellikle LLM) saniyeler sürebilir. Bu sürede olay döngüsü
kilitlenirse hiçbir mesaj işlenemez (Faz 6'da ACİL DUR dahil!). Bu yüzden
parser `run_in_executor` ile ayrı bir thread'de çalışır:

```python
cozum = await asyncio.get_running_loop().run_in_executor(None, self.cozucu.coz, metin)
```

## 6. Dart dersleri

- **switch ifadesi ve desen eşleme (Dart 3):**
  ```dart
  if (k.durum case KartDurumu.dinleniyor || KartDurumu.isleniyor) k.durum = KartDurumu.duyuldu;
  ```
  Mesajlar ağda sırasız gelebilir. `komut` daha önce geldiyse geç gelen `duyuldu` kartı geri çekmesin.
- **Kayıt (record) ile çoklu dönüş:** `final (renk, yazi) = switch (d) { ... => (Colors.red, 'REDDEDİLDİ') }`
- **`JsonEncoder.withIndent('  ')`:** JSON'u ekranda okunur göstermek için.
- **`ListView.builder`:** Sadece ekranda görünen kartlar çizilir; yüzlerce kart olsa da akıcı kalır.
- **`SelectableText`:** Kartta JSON'u seçip kopyalayabilirsin (hata bildirirken işe yarar).

## 7. Dene

```bash
cd kopru && python3 -m pytest -q                     # 27 test (deneme sunucusu gerçek parser'la)
cd ../mobil && flutter test && ../scripts/uyum_testi.sh

# Elle:
cd kopru && python3 -m mobile_bridge.deneme_sunucusu --token ABC
URL='ws://127.0.0.1:8765/telsiz?token=ABC'
python3 -m mobile_bridge.sahte_telefon --url $URL --metin "beş yüz metre yüksel"
#   -> komut {"adimlar":[{"komut":"yuksel","metre":500.0}]}
#   -> geri_bildirim reddedildi "yerdeyim, önce kalkış yapmalıyım"
python3 -m mobile_bridge.sahte_telefon --url $URL --metin "kalk" --bekle 5
python3 -m mobile_bridge.sahte_telefon --url $URL --metin "beş yüz metre yüksel"
#   -> geri_bildirim reddedildi "hedef irtifa 510 m, sınır 120 m"
```

LLM ile denemek için drone reposunda `./scripts/llama_server.sh` çalıştır,
sonra `deneme_sunucusu --llm http://127.0.0.1:8080`.

**Kendin dene:**
1. "biraz yükselsene kırk metre kadar" yaz. LLM kapalıyken kart `ANLAŞILMADI` olur (hızlı yol bu serbest cümleyi bilmez). LLM açıkken `LLM` rozetiyle çözülür.
2. Arka arkaya hızlıca üç hızlı tuşa bas. Her komutun doğru kartına gittiğini (eşleştirme kuyruğu) gör.

## Sonraki faz

**Faz 6:** Güvenlik. ACİL DUR yer istasyonuna gidecek. Telsiz koparsa drone
duracak. LLM düşünürken basılan ACİL DUR, gecikmeli gelen eski komutu iptal
edecek.
