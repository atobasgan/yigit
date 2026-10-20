# Faz 10 — Bütün sistem: ROS 2 köprüsü, PX4 telemetrisi, sesli yanıt, ayarlar, QR

> **Bu fazın sonunda:** Köprü gerçek bir **ROS 2 node'u** olarak çalışabiliyor
> (`bridge_node`). Telefonun üstünde **telemetri şeridi** var: irtifa, hız,
> yön, batarya, uçuş modu. Telefon olanları **Türkçe sesle** söylüyor
> ("20 metre yükseliyorum", "Reddedildi. sınır 120 m"). **Ayarlar ekranı**
> var. Bağlanmak için adres yazmak yerine terminaldeki **QR kodu** okutmak
> yetiyor. Ekran telsiz açıkken kararmıyor.

## 1. Bütün resim

```
 TELEFON (Flutter)                       YER İSTASYONU (bilgisayar)                        DRONE
┌──────────────────────┐   Wi-Fi    ┌─────────────────────────────────────────┐
│ [BAS KONUŞ]          │ WebSocket  │ mobile_bridge (bridge_node)             │
│  ├ telefon STT ──metin──────────> │  ├ /voice/text ──> command_parser ──┐   │
│  └ ham ses ─20 ms PCM──────────>  │  │  (STT: faster-whisper)            │   │
│ [ACİL DUR] ─acil_dur───────────>  │  ├ /drone/emergency_stop ──┐        │   │
│                      │            │  │                          ▼        ▼   │
│ kartlar  <──komut, geri_bildirim─ │  ├ /drone/command, /drone/feedback      │   uXRCE-DDS
│ telemetri <─telemetri (2 Hz)───── │  └ PX4 telemetrisi <── px4_interface ◄──┼──────────── PX4
│ TTS: "yükseliyorum"  │            │                  mission_executor ──────┼──────────► (offboard)
└──────────────────────┘            └─────────────────────────────────────────┘
```

Faz 1'den beri yazdığımız her parça bu resimde bir yerde duruyor:

| Parça | Faz |
|---|---|
| Bas-konuş tuşu, tema | 1 |
| Protokol (JSON + ikili çerçeve) | 2 |
| Köprü çekirdeği + asyncio sunucu | 3 |
| Telefon istemcisi, yeniden bağlanma | 4 |
| Metin → command_parser → JSON → kart | 5 |
| ACİL DUR, kalp atışı, nesil sayacı | 6 |
| Telefon STT | 7 |
| Ham ses akışı, ön kayıt | 8 |
| faster-whisper, kayıt | 9 |
| **ROS 2 node, telemetri, TTS, ayarlar, QR** | **10** |

## 2. Faz 3'teki kararın meyvesi: çekirdek değişmedi

Faz 3'te köprüyü ikiye ayırmıştık:

- **Çekirdek** (`cekirdek.py`): Bütün kurallar. Ağ yok, ROS yok, saat dışarıdan.
- **Kabuk**: Çekirdeği dünyaya bağlayan ince katman.

Şimdiye kadar tek kabuğumuz `deneme_sunucusu.py` idi (ROS yerine sanal drone).
Bu fazda ikinci kabuk geliyor: **`bridge_node.py`**. İkisi de **aynı**
çekirdeği kullanıyor:

```
                ┌─ deneme_sunucusu.SanalDrone  (RosArayuzu'nu sanal drone ile doldurur)
TelsizCekirdegi ┤
                └─ bridge_node._RosKoprusu     (RosArayuzu'nu ROS topic'leriyle doldurur)
```

`RosArayuzu`, çekirdeğin dış dünyadan istediği 4 şeydir:

```python
class _RosKoprusu(RosArayuzu):
    def metin_yayinla(self, metin):       self.node.metin_pub.publish(String(data=metin))
    def acil_dur_yayinla(self):           self.node.acil_pub.publish(Empty())
    def konusma_yayinla(self, k, kaynak): ...AudioUtterance...      # istege bagli
    def stt_baslat(self, konusma):        self.node.stt_isleri.submit(self.node.stt_calistir, konusma)
```

Sonuç: ACİL DUR, telsiz kopması, nesil sayacı, operatör/izleyici, ses
birleştirme gibi bütün kurallar Faz 3-9'da **ROS olmadan** test edildi. Gerçek
node'a geçerken bu kuralların hiçbiri yeniden yazılmadı. Buna "mantığı
çerçeveden (framework) bağımsız tutmak" denir. Bir sistemin en riskli kısmını
en kolay test edilir yerde tutar.

## 3. Bir node, iki dünya: rclpy ve asyncio

ROS 2'nin Python kütüphanesi `rclpy` kendi döngüsüyle çalışır (`rclpy.spin`).
WebSocket sunucumuz ise `asyncio` döngüsü istiyor. **İki döngü aynı thread'de
dönemez**: biri dönerken diğeri bekler.

Çözüm: Her döngüye bir thread.

```
ana thread:     rclpy.spin(node)          ROS callback'leri: /drone/command, /drone/feedback, telemetri timer
yan thread:     asyncio.run(sunucu.calis()) WebSocket: telefonlar, ping, ACİL DUR
STT thread'i:   ThreadPoolExecutor(1)      faster-whisper (1.5 sn)
```

```python
self._thread = threading.Thread(target=self._sunucu_dongusu, daemon=True)   # asyncio burada
...
rclpy.spin(node)                                                              # ROS burada
```

**Thread'ler arası köprü: `sunucu.disaridan()`**

ROS callback'i (ana thread) çekirdeğe dokunmak istediğinde bunu doğrudan
yapmaz. İşi asyncio thread'ine **sıraya koyar**:

```python
def _komut_cb(self, msg):                                  # ROS thread'inde çalışır
    self.sunucu.disaridan(self.cekirdek.ros_komut, komut_listesi_sozlugu(msg))

def disaridan(self, fonksiyon, *args):                     # sunucu.py
    self._dongu.call_soon_threadsafe(lambda: ...fonksiyon(*args)... -> telefonlara gönder)
```

Böylece çekirdek **her zaman tek bir thread'den** (asyncio) çağrılır. Kilit
(`Lock`) gerekmez, yarış durumu oluşmaz. Faz 9'da STT sonucu da aynı yoldan
dönüyordu.

> **Genel kural:** Paylaşılan duruma tek bir thread dokunsun; diğerleri ona
> mesaj göndersin. Kilit kullanmaktan çoğu zaman daha basit ve daha güvenlidir.

### Topic tablosu

| Yön | Topic | Mesaj | Ne zaman |
|---|---|---|---|
| köprü → | `/voice/text` | `std_msgs/String` | telefon metni ya da yer STT sonucu |
| köprü → | `/drone/emergency_stop` | `std_msgs/Empty` | ACİL DUR tuşu, telsiz koptu |
| köprü → | `/voice/utterance` | `drone_interfaces/AudioUtterance` | her bas-konuş (varsa; ileride ayrı stt_node için) |
| → köprü | `/drone/command` | `drone_interfaces/CommandList` | parser JSON üretti → telefona `komut` |
| → köprü | `/drone/feedback` | `drone_interfaces/Feedback` | yürütücü / parser → telefona `geri_bildirim` |
| → köprü | `/fmu/out/...` | `px4_msgs` | PX4 konum, durum, batarya → telefona `telemetri` |

`donustur.py`, ROS mesajlarını telefona gidecek sade sözlüklere çevirir.
ROS'suz test edilir (`test_donustur.py`): `DroneCommand(komut='kalk', metre=10)`
→ `{"komut": "kalk", "irtifa_m": 10}`. Telefon, LLM'in ürettiği şemanın
**aynısını** görür.

### İsteğe bağlı import

```python
try:
    from drone_interfaces.msg import AudioUtterance
except ImportError:          # drone_interfaces eski derlemeyse
    AudioUtterance = None
```

Köprü, eksik bir parça yüzünden tamamen çalışmaz hale gelmemeli. `px4_msgs`
yoksa telemetri gelmez ama telsiz yine çalışır. Bu, Faz 6'daki "şüphede güvenli
tarafta kal" ilkesinin yazılımdaki karşılığı: **zarif bozulma** (graceful
degradation).

## 4. PX4 telemetrisi

```
PX4 ──uXRCE-DDS──> /fmu/out/vehicle_local_position, vehicle_status, battery_status ...
                   └─> PX4Arayuz(node, komut_yayinlari=False)   (drone reposu, mission_executor)
                       └─> donustur.telemetri_sozlugu(px4)       2 Hz timer
                           └─> cekirdek.telemetri(veri) ──> HERKES: {"tip":"telemetri", ...}
```

Telefona giden mesaj (deneme sunucusundan gerçek çıktı, `kalk`tan sonra):

```json
{"tip":"telemetri","hazir":true,"irtifa":10.0,"hiz":0.0,"yaw":0,"x":0.0,"y":0.0,
 "batarya":0.99,"arm":true,"havada":true,"mod":"OFFBOARD"}
```

**`komut_yayinlari=False` neden?** `PX4Arayuz` normalde PX4'e komut da
yayınlar (offboard setpoint, arm). Köprü sadece **okumalı**. İki node aynı
topic'e setpoint yayınlarsa PX4 iki farklı hedef görür. Bu yüzden drone
reposundaki sınıfa bir parametre ekledik (patch'te).

**Neden 2 Hz?** Ekrandaki bir sayının saniyede 2 kez güncellenmesi gözle
yeterli. PX4 bu verileri 50-100 Hz üretir; hepsini Wi-Fi'dan göndermek boşa
bant harcar. **Örnekleme (downsampling)**: Kaynağın hızı ile gösterimin hızı
farklı olabilir.

**Telemetrinin güvenlikte rolü:** Faz 6'da "drone yerdeyse telsiz kopunca dur
gönderme" demiştik. Ama `havada` bilgisini deneme sunucusu kendisi ayarlıyordu.
Artık telemetriden geliyor:

```python
def telemetri(self, veri):
    self.son_telemetri = veri
    self.havada = veri.get('havada')     # kalp atisi kurali bunu kullanir
```

Yeni bağlanan telefon da son telemetriyi `hos_geldin`'in hemen ardından alır;
bir sonraki mesajı beklemeden ekranı dolar.

### Telefon tarafı

`Telemetri` (`lib/durum/modeller.dart`) **değişmez (immutable)** bir sınıf.
Her mesajda yenisi oluşturulur, alanları sonradan değiştirilmez:

```dart
case 'telemetri':
  telemetri = Telemetri.fromJson(m);      // eskisini değiştirmek yerine yenisiyle değiştir
```

`fromJson` içindeki küçük ama önemli ayrıntı:

```dart
double? d(String k) => (j[k] as num?)?.toDouble();
```

JSON'da `10` (int) ve `10.0` (double) farklı tiplerdir. Python `round(10.0, 1)`
ile `10.0` gönderir ama başka bir köprü `10` gönderebilir. `as double` yazsaydık
`10` geldiğinde uygulama çökerdi. `num` ikisini de kapsar. Test:
`'irtifa': 20` → `20.0`.

`TelemetriSeridi` (`lib/bilesenler/telemetri_seridi.dart`):

```
┌──────────────────────────────────────────────────────────┐
│ İRTİFA   HIZ      YÖN   BATARYA  MOD        ARM          │
│ 10.0 m   0.0 m/s  0°    %99      OFFBOARD   HAVADA       │
└──────────────────────────────────────────────────────────┘
```

- `Wrap`: Dar ekranda değerler alt satıra kayar, taşma hatası olmaz.
- Batarya %30'un altına düşünce kırmızı yazılır.
- `hazir: false` ise "telemetri bekleniyor (PX4 bağlı mı?)" yazar. Eksik veriyi
  "0 m" diye göstermek yanıltıcı olurdu.

## 5. Türkçe sesli yanıt (TTS)

Operatör drone'a bakarken ekrana bakamaz. Faz 6'da titreşim dilini kurmuştuk,
şimdi bir de ses ekliyoruz. `flutter_tts` paketi telefonun **kendi** konuşma
sentezleyicisini kullanır (Android `TextToSpeech`, iOS `AVSpeechSynthesizer`):
internet ve model indirme gerekmez.

`GeriBildirimci` arayüzüne iki metot eklendi:

```dart
abstract class GeriBildirimci {
  Future<void> soyle(String metin);
  Future<void> sustur();
  void titresim(Titresim tur);
}
```

**Ne söylenir, ne söylenmez?**

| Olay | Ses | Neden |
|---|---|---|
| `yurutuyor` | "20 metre yükseliyorum" | Komutun **doğru anlaşıldığının** sesli teyidi |
| `reddedildi` | "Reddedildi. sınır 120 m" | Neden yapılmadığını bilmek gerekir |
| `anlasilmadi` | "Anlamadım" | Tekrar söylemesi gerektiğini bilsin |
| ACİL DUR / telsiz koptu | "Acil dur" / "Telsiz bağlantısı koptu" | En önemli iki uyarı |
| `tamamlandi`, `kabul` | — | Çok sık gelir; her şeyi söyleyen sistem dinlenmez |

Gerçek telsiz kültüründen iki kural:

1. **Yeni haber eskisini keser.** `soyle()` önce `stop()` çağırır. Sırada 3 cümle birikirse operatör 5 sn önceki durumu dinler.
2. **Konuşan araya girer.** Bas-konuş tuşuna basılınca `sustur()` çağrılır. Hem operatör kendi sesini rahat duyar, hem de TTS sesi mikrofona girip STT'yi bozmaz.

```dart
Future<void> pttBasla() async {
  geriBildirim.titresim(Titresim.basla);
  unawaited(geriBildirim.sustur());
```

**`unawaited` nedir?** `soyle()` bir `Future` döndürür. Bunu `await` etseydik
kontrolcü cümle bitene kadar (2-3 sn) beklerdi. `unawaited(...)` "bunu bilerek
beklemiyorum" demektir. Okuyan kişi unutulmuş bir `await` ile bilinçli olanı
ayırt eder. (`analysis_options.yaml`'da `unawaited_futures` kuralı açılırsa
analizci işaretlenmemiş her Future'ı uyarı olarak gösterir.)

Test: `SahteGeriBildirim.soylenen` listesi. Gerçek ses çıkmaz, ne söyleneceği
doğrulanır (`test/faz10_test.dart`).

## 6. Ayarlar ekranı

Faz 4'ten beri ayarlar vardı (`Ayarlar` sınıfı, `shared_preferences`) ama
ekranı yoktu. `lib/ekranlar/ayarlar_ekrani.dart`:

- **Konuşma tanıma:** otomatik / telefonda / yer istasyonunda (Faz 7-8), internetsiz tanıma
- **Ses:** ön kayıt, son kayıt süresi (`Slider`), gürültü bastırma
- **Geri bildirim:** sesli yanıt, titreşim
- **Bağlantı:** adres, rol, bağlantıyı kes

Flutter dersleri:

- **Navigator:** Ekranlar bir **yığın** (stack) gibidir. `push` yeni ekranı üste koyar, geri tuşu `pop` eder.
  ```dart
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AyarlarEkrani(kontrolcu: k)));
  ```
- **`RadioGroup` (Flutter 3.32+):** Eskiden her `Radio`'ya ayrı `groupValue` ve `onChanged` verilirdi. Yeni API'de seçili değer ve değişiklik **bir kez**, grubun üstünde tanımlanır; düğmeler sadece kendi `value`'larını bilir.
- **Tek doğruluk kaynağı:** Ekran kendi kopyasını tutmaz; `kontrolcu.ayarlar`'ı okur, değişikliği `ayarlariGuncelle()` ile gönderir ve `ListenableBuilder` ile yeniden çizilir. Ayar hem kontrolcüye (mikrofon, TTS hemen değişir) hem depoya (uygulama kapanınca kalır) gider.

## 7. QR ile bağlanma

`ws://192.168.1.20:8765/telsiz?token=Xy3...` gibi bir adresi telefonda yazmak
hem zahmetli hem de hata yapmaya açık. Köprü bu adresi terminalde QR kod olarak
basar (`kopru/mobile_bridge/qr_kod.py`, `pip install qrcode`):

```
Deneme sunucusu (ROS yok). Telefonda okut ya da yaz:
ws://192.168.1.20:8799/telsiz?token=ABC
█▀▀▀▀▀▀▀█▀██▀▀█▀███▀███▀▀▀▀▀▀▀█
█ █▀▀▀█ ██▄█▄▀▀█▀▀▄  ██ █▀▀▀█ █
█ █   █ █   █▄▀ ██ █▄▀█ █   █ █
...
```

Bir terminal karakteri (`▀`, `▄`, `█`) **iki** QR pikselini (üst ve alt yarı)
gösterir. Böylece QR kare görünür ve ekrana sığar.

Telefon tarafında `mobile_scanner` kamerayı açar:

```dart
// bağlan ekranı: tarayıcıyı aç, sonucunu BEKLE
final okunan = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const QrTarayiciEkrani()));

// tarayıcı ekranı: ilk geçerli kodda kapan ve değeri geri ver
onDetect: (yakalanan) {
  if (_bitti) return;                 // kamera saniyede onlarca kare yakalar!
  ... if (deger.startsWith('ws')) { _bitti = true; Navigator.of(context).pop(deger); }
}
```

- **`push<String>` bir `Future` döndürür.** Açılan ekran `pop(deger)` dediğinde tamamlanır. Ekranlar arasında veri döndürmenin standart yoludur.
- **`_bitti` bayrağı:** `onDetect` aynı QR için art arda birçok kez çağrılır. Bayrak olmasaydı `pop` iki kez çalışır ve bağlan ekranını da kapatırdı.
- Okunan değer Faz 2'deki `BaglantiAdresi.coz()`'dan geçer. QR'dan gelen veri de **dışarıdan gelen veridir**, doğrulanmadan kullanılmaz.

İzinler:

| Platform | Ekleme | Neden |
|---|---|---|
| Android | `<uses-permission android:name="android.permission.CAMERA" />` | QR için kamera |
| Android | `<intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>` | Android 11+ paket görünürlüğü: TTS motorunu görmek için (Faz 7'deki `RecognitionService` ile aynı mantık) |
| Android | `BLUETOOTH_CONNECT` | Android 12+: Bluetooth kulaklık mikrofonu |
| iOS | `NSCameraUsageDescription` | Kamera izni penceresindeki açıklama. Yoksa uygulama çöker |

## 8. Ekran kararmasın: `wakelock_plus`

```dart
await WakelockPlus.enable();          // main.dart
```

Telefon 30 sn sonra kilitlenirse operatör ACİL DUR'a basmadan önce kilidi
açmak zorunda kalır. Telsiz uygulamasında bu kabul edilemez. Bedeli pil
tüketimi; koyu tema (Faz 1) OLED ekranlarda bunu biraz azaltır.

## 9. Drone reposuna yapılacaklar (`ros2/`)

Köprü artık bir ROS 2 paketi: `kopru/` içinde `package.xml`, `setup.py`,
`setup.cfg`, `resource/mobile_bridge` var. Drone reposunda gereken küçük
değişiklikler `ros2/drone_reposu.patch`'te:

| Değişiklik | Neden |
|---|---|
| `drone_interfaces/msg/AudioUtterance.msg` | `/voice/utterance` mesajı |
| `drone_interfaces/msg/Feedback.msg` → `iptal` durumu | Faz 6'daki nesil sayacının ROS karşılığı |
| `command_parser/parser_node.py` | `/drone/emergency_stop`'u dinler; çözülürken ACİL DUR geldiyse sonucu atar (Faz 6, §4) |
| `mission_executor/px4_interface.py` | `komut_yayinlari=False`: köprü sadece okur |
| `drone_bringup/launch/telsiz.launch.py`, `config/telsiz.yaml` | Hepsini birlikte başlatma |

```bash
cd ~/drone && git apply --check ~/yigit/ros2/drone_reposu.patch && git apply ~/yigit/ros2/drone_reposu.patch
ln -s ~/yigit/kopru ~/drone/ros2_ws/src/mobile_bridge
cd ~/drone/ros2_ws && colcon build --symlink-install && source install/setup.bash
```

`telsiz.yaml`'dan önemli parametreler:

```yaml
token_env: TELSIZ_TOKEN        # anahtar dosyada değil ORTAM DEĞİŞKENİNDE; yoksa her açılışta rastgele
baglanti_koparsa: dur          # Faz 6
stt_motoru: yok                # faster_whisper -> yer STT modu (Faz 9)
stt_hesaplama: int8            # CPU'da (Faz 9 ölçümü); GPU'da float16
telemetri_hz: 2.0
kayit_klasoru: ""              # dolu ise WAV + etiketler.csv (Faz 9)
```

## 10. Tam sistemi çalıştırmak

```bash
# 1) PX4 SITL + Gazebo + MicroXRCEAgent (drone reposu: scripts/hepsini_baslat.sh)
# 2) LLM (isteğe bağlı): drone reposu ./scripts/llama_server.sh
# 3) Köprü + parser + yürütücü:
export TELSIZ_TOKEN=benim-gizli-anahtarim
ros2 launch drone_bringup telsiz.launch.py
# 4) Telefonda: uygulamayı aç -> "QR kodu okut" -> terminaldeki QR
```

ROS yoksa aynı deneyimin sanal hali (Faz 5'ten beri):

```bash
cd kopru && python3 -m mobile_bridge.deneme_sunucusu --stt faster_whisper
```

Telefon iki durumu **ayırt edemez**. İkisi aynı protokolü konuşur; deneme
sunucusunun sanal telemetrisi de `telemetri_sozlugu` ile aynı alanları
gönderir. Uyum testi (`scripts/uyum_testi.sh`) artık telemetriyi de kontrol
ediyor: `kalk`tan sonra `havada: true`, `irtifa: 10.0`, `mod: OFFBOARD`.

## 11. Neyi doğruladık, neyi doğrulayamadık?

Dürüst bir proje, test edilmemiş şeyi "çalışıyor" diye sunmaz.

| | Durum |
|---|---|
| Çekirdek kuralları (telemetri dahil) | ✓ birim testleri (Python 51 test) |
| Deneme sunucusu + gerçek parser + güvenlik + sanal telemetri | ✓ testler ve elle çalıştırma (yukarıdaki çıktılar gerçek) |
| Dart istemci ↔ Python köprü (telemetri, ses, ACİL DUR) | ✓ uyum testi |
| Telefon mantığı, TTS çağrıları, ayarlar ekranı, telemetri şeridi | ✓ Flutter 45 test |
| Terminal QR | ✓ elle çalıştırıldı |
| `bridge_node.py` gerçek ROS 2 ile | ✗ Bu bulut ortamında ROS 2 yok. Kod drone reposunun `mobil-telsiz` dalındaki node ile aynı; yalnızca `py_compile` ve flake8 ile denetlendi |
| Gerçek telefonda çalıştırma (APK, kamera, TTS sesi, mikrofon) | ✗ Bu ortamda telefon/emülatör yok. `flutter run` ile ilk denemende izin pencerelerine ve Türkçe TTS paketine dikkat et |
| PX4'ten gerçek telemetri | ✗ (ROS gerektiriyor) |

Sanal drone'un bir sınırlaması: telemetri adım **bitince** güncellenir.
`kalk` sırasında irtifa 0'dan 10'a "sıçrar"; gerçek PX4'te ara değerler akar.

## 12. Sonraki adımlar (bu reponun dışında kalanlar)

- **Arka planda çalışma:** Telefon ekranı kapanınca ya da başka uygulamaya geçilince bağlantı kopar. Android'de *foreground service* (bildirimde "telsiz açık" yazar), iOS'ta *background audio* modu gerekir.
- **Donanım PTT:** Ekrana dokunmak yerine Bluetooth bir düğme ya da telefonun ses tuşu. Eldivenle ve ekrana bakmadan kullanım için.
- **`wss://` (TLS):** Şu an yerel ağda şifresiz `ws://` kullanılıyor (token var ama trafik okunabilir). Ortak ağlarda ya da internet üzerinden şifreleme şart.
- **Opus sıkıştırma:** Mobil veri ya da VPN gibi yavaş bağlantılarda 32 KB/sn → ~3 KB/sn (Faz 8 bant hesabı).
- **Harita:** Telemetride `enlem/boylam` zaten var; `flutter_map` ile drone'un konumu.
- **Veri döngüsü:** Faz 9'daki kayıtlarla STT ölçümü, drone reposunda LLM fine-tune ve sonra Whisper ince ayarı.

## 13. Dene

```bash
cd kopru && python3 -m pytest -q                          # 51 test (+1 isteğe bağlı)
cd ../mobil && flutter analyze && flutter test            # 45 test (+1 uyum)
cd .. && ./scripts/uyum_testi.sh                          # gerçek Dart <-> gerçek Python

pip install qrcode
cd kopru && python3 -m mobile_bridge.deneme_sunucusu      # terminalde QR
python3 -m mobile_bridge.sahte_telefon --url $URL --metin kalk --bekle 5 --telemetri
cd ../mobil && flutter run                                # telefonda: QR kodu okut
```

**Kendin dene:**
1. `TelemetriSeridi`'ne `x, y` (eve uzaklık) değerini ekle: `sqrt(x² + y²)` m. Telemetri mesajında alanlar zaten var; protokolü değiştirmen gerekmiyor.
2. `tamamlandi` durumunda da "tamam" desin. Arka arkaya üç komut ver. Fazla mı konuşuyor? Kendi kuralını belirle.
3. Telefon bağlıyken köprüyü kapat ve yeniden aç. Telemetri şeridi ne gösteriyor? "Son telemetri X sn önce" uyarısını nasıl eklerdin? (İpucu: `Telemetri`'ye alınma zamanı ekle, `Timer.periodic` ile kontrol et.)

## Kapanış

On fazda telefonu bir drone telsizine çevirdik:

- **Flutter:** widget, durum yönetimi (`ChangeNotifier`), platform eklentileri, izinler, testler.
- **Ağ:** WebSocket, JSON ve ikili çerçeve, ping, yeniden bağlanma.
- **Ses:** PCM, örnekleme, halka tampon, STT (telefonda ve yer istasyonunda).
- **Güvenlik:** ACİL DUR, kalp atışı, yarış durumları.
- **Mimari:** Çekirdek/kabuk ayrımı, arayüz + sahte nesne, thread'ler arası mesajlaşma.

Bir sonraki adımlar drone reposunda: fine-tune (Faz 4) ve sahada gerçek uçuş.
