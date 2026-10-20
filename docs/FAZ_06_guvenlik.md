# Faz 6 — Güvenlik: ACİL DUR, telsiz kopması, gecikmeli komutlar

> **Bu fazın sonunda:** Kırmızı **ACİL DUR** tuşu gerçekten yer istasyonuna
> gidiyor; izleyiciler de basabiliyor. Operatörün telsizi koparsa drone
> kendiliğinden duruyor. LLM bir cümleyi düşünürken ACİL DUR'a basılırsa,
> geç gelen o komut **iptal ediliyor**. Telefon her olayda farklı bir
> titreşimle haber veriyor.

## 1. Güvenlik tasarımında soru: "Ne ters gidebilir?"

Drone sistemlerinde özellikler "her şey yolundayken ne olur?" diye tasarlanır.
Güvenlik ise "**ters giderse** ne olur?" diye düşünülerek tasarlanır. Bu fazda
dört başarısızlık durumuna cevap veriyoruz:

| Ne ters gidebilir? | Çözüm | Nerede |
|---|---|---|
| Operatör "dur" demek istiyor ama ses/LLM yavaş | Ayrı ACİL DUR tuşu: STT'ye ve LLM'e hiç uğramaz | telefon `acilDur()`, köprü `acil_dur` |
| Operatör bayıldı, telefonu düşürdü, Wi-Fi gitti | Kalp atışı kesilirse köprü drone'u durdurur | `cekirdek.tik()` |
| Operatör uzakta, yanındaki biri tehlikeyi görüyor | İzleyici de ACİL DUR verebilir | `cekirdek.metin_cercevesi` |
| LLM düşünürken "dur" denildi, eski komut geç geldi | Nesil sayacı: dur'dan önce başlayan sonuç atılır | `deneme_sunucusu`, drone reposunda `parser_node` |

Ana ilke: **şüphede kal, drone'u durdur.** Yanlışlıkla durmak, yanlışlıkla
hareket etmekten her zaman daha az tehlikelidir.

## 2. ACİL DUR: telefonun yorum yapmadan verdiği tek karar

```
[ACİL DUR] ──{"tip":"acil_dur"}──> köprü ──/drone/emergency_stop (Empty)──> yürütücü: kuyruğu boşalt, yerinde kal
                                       └──> HERKES: {"tip":"geri_bildirim","durum":"acil_dur","mesaj":"ACİL DUR (Pixel 8)"}
```

Faz 5'te "telefon komutu yorumlamaz" dedik. ACİL DUR bu kuralın tek
istisnası. Yorum değil, doğrudan durdurma:

- Konuşma tanımaya gitmez (yanlış duyulamaz).
- LLM'e gitmez (saniyelerce beklemez).
- Güvenlik katmanının izin vermesini beklemez; durmak her zaman güvenlidir.
- **Onay sormaz.** "Emin misiniz?" diyaloğu acil durumda öldürücü bir gecikmedir.

**İzleyici de basabilir.** Faz 3'te izleyicileri komut vermekten men ettik.
ACİL DUR hareket değil durma olduğu için bu yasak ona uygulanmaz:
`acil_dur` kontrolü, `operator_degil` kontrolünden **önce** yapılır.

Gerçek çalıştırma (operatör kalktı, sonra izleyici durdurdu):

```
OPERATÖR <- {"tip":"geri_bildirim","id":2837,"durum":"yurutuyor","mesaj":"kalkıyorum"}
OPERATÖR <- {"tip":"geri_bildirim","id":2837,"durum":"tamamlandi","mesaj":"kalk tamamlandı"}
İZLEYİCİ <- {"tip":"geri_bildirim","id":null,"durum":"acil_dur","mesaj":"ACİL DUR (sahte_telefon)"}
sunucu:  ACİL DUR      <- operatör (sahte_telefon) programı bitince bağlantı kapandı: drone havadaydı
         ACİL DUR      <- izleyicinin tuşu
```

İlk "ACİL DUR" ilginç: operatörün programı bittiği için bağlantı kapandı ve
drone havadaydı. Köprü bunu "telsiz koptu" sayıp drone'u durdurdu (§3).

## 3. Kalp atışı (heartbeat) ve telsiz kopması

Faz 4'te telefon her saniye `ping` gönderiyordu. Bu fazda köprü bunu
**kalp atışı** olarak kullanıyor:

```python
def tik(self):                       # sunucu 0.5 sn'de bir çağırır
    if self.saat() - op.son_mesaj_t > self.ayarlar.baglanti_zaman_asimi_s:   # 3 sn
        return self._operator_kayboldu('operatörden 3 sn sinyal yok')
```

`_operator_kayboldu`:
- `baglanti_koparsa = 'dur'` (varsayılan) ve drone yerde değilse → `acil_dur_yayinla()`.
- Herkese `{"durum":"telsiz_koptu","mesaj":"...; drone yerinde asılı kalıyor"}` gönderir.
- **Bir kopma için bir kez** çalışır (`_kopma_bildirildi`); her 0.5 sn'de tekrar tekrar dur göndermez. Operatör yeniden bağlanınca sıfırlanır.

**Neden 3 sn?** Telefon 1 sn'de bir ping gönderiyor; Wi-Fi'da bir-iki paketin
gecikmesi normal. 3 sn, gereksiz alarm vermeyecek kadar uzun, drone'un fazla
uzaklaşmayacağı kadar kısa bir değer.

**Neden drone yerdeyken dur gönderilmiyor?** Yerdeki drone zaten durmuş;
gereksiz komut log'ları kirletir. `havada` bilgisi Faz 10'da PX4
telemetrisinden gelecek. Şimdilik deneme sunucusu kendisi ayarlıyor
(`self.cek.havada = self.durum.havada`). Bilinmiyorsa (`None`) güvenli
taraf seçilir: dur gönderilir.

### Saat enjeksiyonu sayesinde test

Kalp atışı testinde 3 saniye beklemiyoruz; sahte saati ileri alıyoruz:

```python
saat.t += 3.5                 # "3.5 saniye geçti"
assert ros.acil == 1          # dur gönderildi
```

Faz 3'te çekirdeğin saati dışarıdan almasının sebebi buydu.

## 4. Yarış durumu (race condition): LLM düşünürken ACİL DUR

Bu fazın en öğretici hatası. Drone reposu üzerinde yaptığımız bir testte
**gerçekten** yaşandı:

```
t=0.0 s   operatör: "önce on metre yüksel ardından doğuya otuz metre git"  -> LLM düşünmeye başladı
t=0.3 s   izleyici: ACİL DUR   -> drone durdu (1.1 ms)
t=3.4 s   LLM sonucu geldi: [yuksel 10, git_yon dogu 30]   -> drone TEKRAR HAREKET EDERDİ!
```

Her parça tek başına doğru çalışıyor. Hata, olayların **sırasında**:
ACİL DUR, kendisinden **önce** başlamış ama **sonra** biten işi bilmiyor.
Bunun adı **yarış durumu**.

Çözüm: **nesil sayacı (generation counter)**.

```python
async def _isle(self, metin):
    nesil = self.acil_nesli              # 1) başlarken nesli not al
    cozum = await ... coz(metin) ...     # 2) LLM saniyeler sürebilir
    if nesil != self.acil_nesli:         # 3) bu sırada ACİL DUR geldi mi?
        -> sonucu AT, "iptal edildi" de
def acil_dur_yayinla(self):
    self.acil_nesli += 1                 # her ACİL DUR yeni bir nesil başlatır
```

Telefonda kart **REDDEDİLDİ** olur ve sebep olarak "ACİL DUR geldiği için …
iptal edildi" yazar. Drone reposundaki gerçek `parser_node.py` de aynı kuralı
`/drone/emergency_stop`'u dinleyerek uygular.

Test: `test_cozulurken_acil_dur_sonucu_iptal_eder`. Yavaş bir sahte LLM 0.5 sn
düşünür, araya ACİL DUR girer, drone'un yükselmediği doğrulanır.

## 5. Telefon tarafı

- `acilDur()`: Bağlı değilse kullanıcıyı **uyarır** ("bağlantı yok: ACİL DUR gönderilemedi!"). Sessizce başarısız olmak burada en kötü davranış olur.
- `geri_bildirim` mesajında `durum == 'acil_dur' | 'telsiz_koptu'` gelirse kırmızı uyarı şeridinde (`MaterialBanner`, `errorContainer` rengi) gösterir.
- **Titreşim dili** (`lib/geri_bildirim/geri_bildirimci.dart`): Operatör ekrana bakmadan ne olduğunu anlayabilsin.

| Olay | Titreşim |
|---|---|
| komut anlaşıldı | `selectionClick` (hafif tık) |
| reddedildi / anlaşılmadı | `heavyImpact` (sert) |
| ACİL DUR / telsiz koptu | `vibrate` (uzun) |

`GeriBildirimci` bir arayüz. Testte `SahteGeriBildirim` hangi titreşimlerin
istendiğini listeler; gerçek telefonda `HapticFeedback` çalışır (ek paket
gerekmez).

## 6. Bir hata hikâyesi (bu fazı hazırlarken)

Bu fazda ekran testi şunu yakaladı: ACİL DUR'a basınca hâlâ "Faz 6'da
gelecek" yazısı çıkıyordu. Sebep: Faz 5'te kod `dart format` ile yeniden
biçimlenmişti. Değişikliği yapan betik eski biçimdeki metni aradı, bulamadı
ve **sessizce hiçbir şey yapmadı**.

Ders: Otomatik değişiklikler "bulamadım" diye bağırmalı. Testler de
gerçekten kullanıcının yaptığını yapmalı: ekran testi tuşa *dokunup*
gönderilen mesajı kontrol ettiği için hatayı yakaladı.

## 7. Dene

```bash
cd kopru && python3 -m pytest -q          # 35 test
cd ../mobil && flutter test && ../scripts/uyum_testi.sh

# Elle (3 terminal):
python3 -m mobile_bridge.deneme_sunucusu --token ABC
python3 -m mobile_bridge.sahte_telefon --url $URL --metin kalk --bekle 30      # operatör
python3 -m mobile_bridge.sahte_telefon --url $URL --acil --izleyici            # izleyici durdurur
```

**Kendin dene:**
1. Telefon bağlıyken Wi-Fi'ı kapat. Sunucu terminalinde ~3 sn sonra `ACİL DUR` yazmalı. Wi-Fi'ı aç; telefon yeniden bağlanır ve operatör olur.
2. `deneme_sunucusu --koparsa devam` ile aynısını dene. Drone durmaz, sadece "devam ediyor" bildirimi gelir. Hangisi daha güvenli? Gerçek uçuşta "eve dön" de bir seçenek olabilir mi?

## Sonraki faz

**Faz 7:** Artık konuşuyoruz. Telefonun kendi Türkçe konuşma tanıyıcısıyla
**bas-konuş**: tuşa bas, konuş, bırak; tanınan metin Faz 5'teki yoldan gitsin.
