# Faz 9 — Yer istasyonunda gerçek Türkçe tanıma (faster-whisper) ve veri toplama

> **Bu fazın sonunda:** Telefondan akan ham ses, yer istasyonunda
> **faster-whisper** ile yazıya çevriliyor ("Kalk.", "20 metre yüksel.").
> Hangi modelin ne kadar sürede ne kadar doğru çevirdiğini **ölçtük**.
> İstenirse her konuşma bir WAV dosyası ve `etiketler.csv` satırı olarak
> kaydediliyor. Bu kayıtlar ileride test seti ve eğitim verisi olacak.
> Telefon tarafında değişiklik yok; Faz 8'deki akış aynen kullanılıyor.

## 1. Whisper ve faster-whisper

**Whisper**, OpenAI'nin açık kaynaklı konuşma tanıma modeli. Türkçe dahil
~100 dil biliyor. Farklı boyutları var:

| Model | Parametre | Disk | Not |
|---|---|---|---|
| tiny | 39 M | ~75 MB | çok hızlı, Türkçe için zayıf |
| base | 74 M | ~145 MB | hızlı, Türkçe için yetersiz (aşağıdaki ölçüm) |
| **small** | 244 M | ~480 MB | **CPU için önerilen** |
| medium | 769 M | ~1.5 GB | daha doğru, yavaş |
| large-v3-turbo | 809 M | ~1.6 GB | GPU varsa en iyi denge |

**faster-whisper**, Whisper'ı **CTranslate2** motoruyla çalıştıran bir
kütüphane. Aynı doğrulukta 2–4 kat daha hızlı çalışır ve az bellek kullanır.
Model ilk kullanımda Hugging Face'ten kendiliğinden iner.

## 2. Ayarlarımız ve nedenleri (`stt_motoru.py`)

```python
model.transcribe(ses,
    language='tr',                         # dil algılama adımını atla (hız + hata azalır)
    beam_size=1,                           # açgözlü (greedy) çözme: en hızlısı
    initial_prompt=DRONE_SOZLUGU,          # "kalk, yüksel, alçal, metre, kuzeye..."
    condition_on_previous_text=False,      # her konuşma bağımsız
    without_timestamps=True)               # zaman damgası üretme: daha az iş
```

- **`initial_prompt` (drone sözlüğü):** Whisper'a "bu kayıtta şu kelimeler geçebilir" ipucu verir. Model bu kelimelere yatkınlaşır: "yüksel" yerine "yüksek", "alçal" yerine "al çal" duyma ihtimali azalır. Faz 7'deki `contextualPhrases` ile aynı fikir.
- **`beam_size=1`:** Model her adımda en olası kelimeyi seçer. 5 farklı aday yolu takip etmek (`beam_size=5`) biraz daha doğru ama belirgin şekilde yavaş. Kısa komutlarda fark azdır.
- **Ses dönüşümü:** Whisper ses örneklerini −1…+1 arası `float32` bekler; PCM16'yı 32768'e böleriz:
  ```python
  ses = np.frombuffer(pcm, dtype='<i2').astype(np.float32) / 32768.0
  ```

## 3. Ölçüm: hangi model, hangi hesaplama?

Piper TTS ile üretilmiş 6 Türkçe komut sesi. Bu bulut sunucusunda **GPU yok,
4 çekirdek CPU** (`araclar/stt_olcum.py` ile ölçüldü):

| model | hesaplama | ort. süre | 6 cümlede doğru |
|---|---|---|---|
| base | int8 | 605 ms | **3/6**: "Kald.", "Yilinimete yüksel.", "Saa 90 derece de." |
| base | float32 | 888 ms | 3/6 |
| small | float32 | 2480 ms | 6/6 |
| **small** | **int8** | **~1500 ms** | **6/6** ← varsayılan |

`small/int8` çıktıları (gerçek):

```
1323 ms  "Kalk."
1614 ms  "20 metre yüksel."
1733 ms  "Önce 20 metre yüksel, sonra kuzeye 50 metre git."
1473 ms  "Sağ 90 derece dön."           <- "sağa" yerine "Sağ" (bkz. §5)
1482 ms  "Dur."
1493 ms  "Eve dön."
```

### int8 nedir? (nicemleme / quantization)

Model ağırlıkları normalde 32 bitlik ondalık sayılardır (`float32`). **int8**
nicemleme bunları 8 bitlik tam sayılara yuvarlar:

- Bellek 4 kat azalır, CPU hesabı hızlanır.
- Doğruluk kaybı genellikle çok küçüktür. Burada ölçülebilir bir kayıp olmadı (6/6), süre %40 kısaldı.
- GPU'da `float16` tercih edilir (GPU'lar 16 bitlik ondalık sayılarda çok hızlıdır).

Drone reposunda LLM için kullandığımız `Q4_K_M` (4 bit) de aynı fikrin daha
agresif bir hali.

### Neden önce ölçtük?

"base hızlı, onu kullanalım" demek kolay. Ölçmeden karar verseydik
"yirmi metre yüksel" "Yilinimete yüksel" olarak duyulacak ve drone hiçbir
komutu anlamayacaktı. Projenin genel ilkesi burada da geçerli:
**önce ölç, sonra karar ver.**

## 4. Uçtan uca gerçek çalıştırma

```bash
python3 -m mobile_bridge.deneme_sunucusu --token ABC --stt faster_whisper --kayit kayitlar/
python3 -m mobile_bridge.sahte_telefon --url $URL --wav kalk.wav
```

```
STT ısınma: 1622 ms                                       <- açılışta bir kez
+     1 ms {"tip":"isleniyor","id":3540,"sure_ms":745,"kayip_parca":0}
+  1484 ms {"tip":"duyuldu","id":3540,"metin":"Kalk.","kaynak":"yer_stt","stt_ms":1482}
+  1485 ms {"tip":"komut","id":3540,"metin":"kalk","kaynak":"hizli_yol","adimlar":[{"komut":"kalk"}]}
```

Okuma:

- Tuş bırakıldıktan 1 ms sonra köprü sesi almıştı (`isleniyor`). Ses tuş basılıyken aktı (Faz 8).
- Sürenin neredeyse tamamı STT'de (1482 ms). Parser ve ağ birkaç ms.
- Whisper'ın "Kalk." çıktısındaki nokta ve büyük harf sorun değil: drone reposundaki `normalize.py` onları temizler ("kalk").

**Isınma:** Bir modelin ilk çağrısı yavaştır (bellek ayırma, önbellek).
Sunucu açılırken 1 sn'lik sessizliği bir kez çevirir (`isit()`); böylece ilk
komutun cezasını operatör ödemez.

GPU'lu bir yer istasyonunda STT'nin ~150–300 ms sürmesi beklenir (ölçülmedi).
Bu durumda tuş bırakma → komut süresi 0.5 sn'nin altına iner.

## 5. STT hataları sistemi nasıl etkiler?

"sağa doksan derece dön" → Whisper: **"Sağ 90 derece dön."**

- Hızlı yol kesin kalıp arar ("sağa ... dön"); "sağ" eşleşmez → cümle LLM'e gider.
- LLM (drone reposunda ölçüldü) bunu doğru çözdü: `{"komut":"don","yon":"sag","derece":90}`, kaynak `llm`.

Yani sistem katmanlı tasarlandığı için küçük STT hataları "anlaşılmadı"ya
dönüşmüyor, sadece daha yavaş yoldan (LLM) gidiyor. Bu hatalar bir sonraki
adımın, yani **veri toplamanın**, konusu.

## 6. Veri toplama: `--kayit` / `kayit_klasoru`

Kayıt açıkken her bas-konuş konuşması:

```
kayitlar/
├── 20261020_133901_03540.wav       16 kHz mono PCM16 (tam olarak STT'ye giden ses)
├── 20261020_133907_03545.wav
└── etiketler.csv
      dosya;stt_metni;beklenen_metin
      20261020_133901_03540.wav;Kalk.;
      20261020_133907_03545.wav;20 metre yüksel.;
```

`beklenen_metin` sütununu sen doldurursun (gerçekte ne söylendi). Bu dosya:

1. **Test seti** olur. `araclar/stt_olcum.py kayitlar/*.wav` her modelin doğruluğunu bu etiketlerle hesaplar (✓/✗). Model ya da ayar değiştirdiğinde aynı kayıtlarla tekrar ölçersin. Canlı konuşmayla yapılan ölçüm tekrarlanamaz.
2. **Eğitim verisi** olur. Drone reposunun Faz 4'ünde (LLM fine-tune) STT'nin **gerçek** hataları ("Sağ 90 derece dön") veri setine girer. Model temiz metin yerine gerçekte göreceği metinle eğitilir.
3. **STT fine-tune** için de başlangıç olur: yeterince kayıt birikirse Whisper'ın kendisi de bu sesle ince ayarlanabilir.

`;` ayırıcılı CSV kullanıyoruz; Türkçe cümlelerde virgül sık geçer. Metindeki
`;` karakterleri `,` ile değiştirilir.

## 7. Thread'ler: STT neden ayrı çalışıyor?

```
olay döngüsü (asyncio)          STT thread'i (ThreadPoolExecutor)
─────────────────────           ─────────────────────────────────
ptt_bitti geldi
  └─ run_in_executor(stt) ───>  yaziya_cevir()   1.5 sn
ACİL DUR geldi  -> HEMEN işlenir        │
ping/pong devam                          │
  <──── sonuç (disaridan / await) ───────┘
duyuldu -> parser -> komut
```

STT 1.5 sn sürerken olay döngüsü serbest kalır. ACİL DUR, ping ve diğer
telefonlar beklemez. Faz 6'daki yarış durumu kuralı (nesil sayacı) STT
sonuçları için de geçerli: dur'dan önce başlamış bir konuşmanın sonucu
parser'a vardığında atılır.

## 8. Dene

```bash
pip install faster-whisper
cd kopru && python3 -m pytest -q                       # 45 test (+1 isteğe bağlı)
TELSIZ_GERCEK_STT=1 python3 -m pytest -q test/test_stt_motoru.py   # gerçek model (tiny) indirir

python3 -m mobile_bridge.deneme_sunucusu --token ABC --stt faster_whisper --kayit kayitlar/
# telefonda bağlan -> otomatik "yer STT" modu -> konuş
python3 araclar/stt_olcum.py kayitlar/*.wav --modeller base small --hesaplama int8
```

**Kendin dene:**
1. Kendi sesinle 10 komut kaydet (`--kayit`), `etiketler.csv`'de `beklenen_metin`'i doldur, `stt_olcum.py` ile base ve small'ı karşılaştır.
2. `DRONE_SOZLUGU`'nu boşalt (`initial_prompt=None`) ve tekrar ölç. Hangi kelimeler bozuldu?

## Sonraki faz

**Faz 10 (son):** Gerçek ROS 2 node'u (`bridge_node`), PX4 telemetrisi
(irtifa, batarya…), Türkçe sesli yanıt (TTS), ayarlar ekranı ve QR ile
bağlanma. Bütün parçalar birleşiyor.
