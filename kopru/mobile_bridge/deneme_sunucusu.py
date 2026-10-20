"""ROS ve PX4 OLMADAN telsiz uygulamasini denemek icin sunucu.

Telefon gercek kopruyle ayni protokolu konusur. Bu sunucu ROS yerine:
  - metni drone reposundaki GERCEK command_parser hattindan gecirir
    (normalize -> acil kelime -> hizli yol -> istenirse llama-server LLM)
    ve uretilen JSON'u telefona gonderir,
  - komutu GERCEK mission_executor guvenlik katmaniyla, sanal bir drone
    uzerinde kontrol eder; "yurutuyor / tamamlandi / reddedildi" uretir.

    python3 -m mobile_bridge.deneme_sunucusu --token ABC
    python3 -m mobile_bridge.deneme_sunucusu --llm http://127.0.0.1:8080
    python3 -m mobile_bridge.deneme_sunucusu --sahte-stt "kalk"   # her sese "kalk" de (Faz 8)
    python3 -m mobile_bridge.deneme_sunucusu --stt faster_whisper # gercek Turkce STT (Faz 9)
    python3 -m mobile_bridge.deneme_sunucusu --stt faster_whisper --kayit kayitlar/

Faz 10: sanal drone 2 Hz telemetri yayinlar (irtifa, batarya, mod...) ve
baglanti adresi terminalde QR kod olarak cikar (pip install qrcode).
Telefon ve bilgisayar ayni Wi-Fi'da olmali.
"""
import argparse
import asyncio
import os
import secrets
import sys
import time

from .drone_yolu import drone_reposu, yolu_ekle

if not yolu_ekle():
    sys.exit(f'drone reposu bulunamadı: {drone_reposu()}\n'
             'DRONE_REPO ortam değişkenini drone reposunun yoluna ayarla.')

from command_parser.komut_cozucu import KomutCozucu  # noqa: E402
from command_parser.llm_client import LLMIstemcisi  # noqa: E402
from command_parser.schema import msg_alanlarina  # noqa: E402
from mission_executor import mesajlar  # noqa: E402
from mission_executor.planlayici import Poz  # noqa: E402
from mission_executor.safety import AracDurumu, Guvenlik, Limitler, Reddedildi  # noqa: E402

from . import protokol  # noqa: E402
from .cekirdek import Ayarlar, RosArayuzu, TelsizCekirdegi  # noqa: E402
from .qr_kod import terminale_yaz, yerel_ip  # noqa: E402
from .stt_motoru import motor_olustur  # noqa: E402
from .sunucu import TelsizSunucusu  # noqa: E402

# Sanal drone hizlari (gorsel geri bildirim icin; gercek fizik degil)
YATAY_MPS, DIKEY_MPS, DONUS_DPS = 5.0, 3.0, 45.0


class SahteSTT:
    """Her sese ayni metni 'duyan' STT (gercek Whisper Faz 9'da)."""
    ad = 'sahte'
    hazir = True

    def __init__(self, metin):
        self.metin = metin

    def yaziya_cevir(self, pcm, hz):
        return self.metin


class SanalDrone(RosArayuzu):
    """ROS'un yerine: parser + guvenlik + yurutme benzetimi."""

    def __init__(self, cozucu, stt=None, hiz_katsayisi=1.0):
        self.cozucu = cozucu
        self.stt = stt
        self.hiz_katsayisi = hiz_katsayisi
        self.guvenlik = Guvenlik(Limitler(max_irtifa=120.0))
        self.durum = AracDurumu(poz=Poz(), havada=False, batarya=1.0)
        self.sunucu = None
        self._gorev = None
        self.acil_nesli = 0             # her ACIL DUR'da artar

    def _yolla(self, cikti):
        asyncio.ensure_future(self.sunucu._gonder(cikti))

    @property
    def cek(self):
        return self.sunucu.cekirdek

    def metin_yayinla(self, metin):
        # Parser (ozellikle LLM) olay dongusunu BLOKLAMAMALI: ayri thread'de calisir.
        asyncio.ensure_future(self._isle(metin))

    async def _isle(self, metin):
        t0 = time.perf_counter()
        nesil = self.acil_nesli
        cozum = await asyncio.get_running_loop().run_in_executor(None, self.cozucu.coz, metin)
        print(f'  "{metin}" -> {cozum.adimlar or "komut yok"} [{cozum.kaynak}] {cozum.sure_ms:.1f} ms')
        if cozum.kaynak != 'acil' and nesil != self.acil_nesli:
            # Cozulurken ACIL DUR geldi: bu sonuc dur'dan SONRA yurutulmemeli.
            # (Drone reposundaki parser_node da ayni kurali uygular.)
            self._yolla(self.cek.ros_geri_bildirim(
                'iptal', f'ACİL DUR geldiği için "{cozum.metin}" iptal edildi'))
            return
        if not cozum.komut_var:
            self._yolla(self.cek.ros_geri_bildirim(
                'reddedildi', f'anlamadım: "{cozum.metin}" ({cozum.hata})'))
            return
        self._yolla(self.cek.ros_komut({
            'metin': cozum.metin, 'kaynak': cozum.kaynak, 'kuyruga_ekle': cozum.kuyruga_ekle,
            'adimlar': cozum.adimlar, 'parser_ms': round((time.perf_counter() - t0) * 1000, 1)}))
        komutlar = [msg_alanlarina(a) for a in cozum.adimlar]
        if komutlar[0]['komut'] == 'dur':          # sesli/yazili "dur" (acil kelime yolu)
            self.acil_dur_yayinla()
            self._yolla(self.cek.ros_geri_bildirim('tamamlandi', 'duruyorum'))
            return
        try:
            hedefler = self.guvenlik.liste_kontrol_et(komutlar, self.durum)
        except Reddedildi as e:
            self._yolla(self.cek.ros_geri_bildirim('reddedildi', str(e)))
            return
        if self._gorev and not cozum.kuyruga_ekle:
            self._gorev.cancel()
        self._gorev = asyncio.ensure_future(self._yurut(komutlar, hedefler))

    async def _yurut(self, komutlar, hedefler):
        self._yolla(self.cek.ros_geri_bildirim('kabul', f'{len(komutlar)} adım kabul edildi'))
        for komut, hedef in zip(komutlar, hedefler):
            self._yolla(self.cek.ros_geri_bildirim('yurutuyor', mesajlar.baslarken(komut)))
            await asyncio.sleep(self._sure(hedef) / self.hiz_katsayisi)
            d = Guvenlik.sonraki_durum(self.durum, hedef)
            self.durum = AracDurumu(poz=d.poz, havada=d.havada,      # her adim bataryadan %1 yer
                                    batarya=max(0.0, d.batarya - 0.01))
            self._yolla(self.cek.telemetri(self.telemetri()))       # havada bilgisi buradan
            self._yolla(self.cek.ros_geri_bildirim('tamamlandi', f'{komut["komut"]} tamamlandı'))

    def acil_dur_yayinla(self):
        self.acil_nesli += 1
        if self._gorev:
            self._gorev.cancel()                    # yurutulen adimi kes: yerinde kal
            self._gorev = None
        print('  ACİL DUR', flush=True)

    def stt_baslat(self, konusma):
        async def calistir():
            t0 = time.perf_counter()
            dongu = asyncio.get_running_loop()
            try:      # STT de saniyeler surebilir: ayri thread'de
                metin = await dongu.run_in_executor(None, self.stt.yaziya_cevir, konusma.pcm(),
                                                    protokol.ORNEKLEME_HZ)
                hata = None
            except Exception as e:
                metin, hata = '', f'STT hatası: {e}'
            sure = (time.perf_counter() - t0) * 1000
            print(f'  STT #{konusma.konusma_id}: "{metin}" ({sure:.0f} ms)', flush=True)
            self._yolla(self.cek.stt_sonucu(konusma, metin, sure, hata))
        asyncio.ensure_future(calistir())

    def telemetri(self):
        """bridge_node'daki donustur.telemetri_sozlugu ile AYNI alanlar (telefon farki bilmez)."""
        p, d = self.durum.poz, self.durum
        return {'hazir': True, 'irtifa': round(p.irtifa, 1) + 0.0, 'hiz': 0.0,   # +0.0: -0.0 olmasin
                'yaw': round((p.yaw * 57.2958) % 360), 'x': round(p.x, 1), 'y': round(p.y, 1),
                'batarya': round(d.batarya, 2), 'arm': d.havada, 'havada': d.havada,
                'mod': 'OFFBOARD' if d.havada else 'BEKLE (HOLD)'}

    def _sure(self, hedef):
        a, b = self.durum.poz, hedef.poz
        if hedef.tip == 'bekle':
            return hedef.saniye
        yatay = ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5 / YATAY_MPS
        dikey = abs(a.z - b.z) / DIKEY_MPS
        donus = abs(a.yaw - b.yaw) * 57.3 / DONUS_DPS
        return min(max(yatay, dikey, donus, 0.5), 20.0)


async def calis(args, hazir=None):
    llm = None
    if args.llm:
        llm = LLMIstemcisi(url=args.llm)
        if llm.saglikli():
            print(f'LLM {args.llm}: ısınma {llm.isit().sure_ms:.0f} ms')
        else:
            print(f'LLM {args.llm} ERİŞİLEMİYOR (sadece hızlı yol)')
    if args.sahte_stt is not None:
        stt = SahteSTT(args.sahte_stt)
    elif args.stt != 'yok':
        print(f'STT modeli yükleniyor: {args.stt_model} ({args.stt_hesaplama}) ...', flush=True)
        stt = motor_olustur(args.stt, model=args.stt_model, hesaplama=args.stt_hesaplama)
        print(f'STT ısınma: {stt.isit():.0f} ms')      # ilk cagri yavas: acilista ode
    else:
        stt = None
    drone = SanalDrone(KomutCozucu(llm=llm), stt, hiz_katsayisi=args.hiz)
    token = args.token or os.environ.get('TELSIZ_TOKEN') or secrets.token_urlsafe(9)
    cekirdek = TelsizCekirdegi(drone, Ayarlar(token=token, baglanti_koparsa=args.koparsa,
                                              kayit_klasoru=args.kayit),
                               stt_hazir=stt is not None, stt_adi=stt.ad if stt else 'yok')
    sunucu = TelsizSunucusu(cekirdek, args.host, args.port)
    drone.sunucu = sunucu
    gorev = asyncio.ensure_future(sunucu.calis())
    await sunucu.hazir_bekle()
    adres = protokol.baglanti_adresi(args.ilan_ip or yerel_ip(), sunucu.port, token)
    print(f'\nDeneme sunucusu (ROS yok). Telefonda okut ya da yaz:\n{adres}\n{terminale_yaz(adres)}')
    print(f'STT: {stt.ad if stt else "yok"} | LLM: {args.llm or "yok"} | Ctrl+C ile çık\n', flush=True)
    if hazir:
        hazir(sunucu, adres)

    async def telemetri_dongusu():          # gercek koprude: bridge_node._telemetri_tik (ROS timer)
        while True:
            await sunucu._gonder(cekirdek.telemetri(drone.telemetri()))
            await asyncio.sleep(0.5)
    t = asyncio.ensure_future(telemetri_dongusu())
    await gorev
    t.cancel()


def arguman_cozucu():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--host', default='0.0.0.0')
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--ilan-ip', default='', help='adreste gösterilecek IP (boş = otomatik)')
    ap.add_argument('--token', default='')
    ap.add_argument('--llm', default='', help='llama-server adresi, ör. http://127.0.0.1:8080')
    ap.add_argument('--hiz', type=float, default=1.0, help='sanal yürütme hız katsayısı')
    ap.add_argument('--koparsa', default='dur', choices=['dur', 'devam'],
                    help='operatör bağlantısı koparsa ne olsun')
    ap.add_argument('--sahte-stt', default=None, help='her ses için bu metni döndür (test)')
    ap.add_argument('--stt', default='yok', choices=['yok', 'faster_whisper'])
    ap.add_argument('--stt-model', default='small', help='tiny | base | small | medium | large-v3-turbo')
    ap.add_argument('--stt-hesaplama', default='int8', help='CPU: int8, GPU: float16')
    ap.add_argument('--kayit', default='', help='konuşmaları WAV + etiketler.csv olarak bu klasöre kaydet')
    return ap


def main(argv=None):
    args = arguman_cozucu().parse_args(argv)
    try:
        asyncio.run(calis(args))
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
