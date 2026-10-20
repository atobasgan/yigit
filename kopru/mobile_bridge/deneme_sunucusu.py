"""ROS ve PX4 OLMADAN telsiz uygulamasini denemek icin sunucu.

Telefon gercek kopruyle ayni protokolu konusur. Bu sunucu ROS yerine:
  - metni drone reposundaki GERCEK command_parser hattindan gecirir
    (normalize -> acil kelime -> hizli yol -> istenirse llama-server LLM)
    ve uretilen JSON'u telefona gonderir,
  - komutu GERCEK mission_executor guvenlik katmaniyla, sanal bir drone
    uzerinde kontrol eder; "yurutuyor / tamamlandi / reddedildi" uretir.

    python3 -m mobile_bridge.deneme_sunucusu --token ABC
    python3 -m mobile_bridge.deneme_sunucusu --llm http://127.0.0.1:8080
"""
import argparse
import asyncio
import os
import secrets
import socket
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
from .sunucu import TelsizSunucusu  # noqa: E402

# Sanal drone hizlari (gorsel geri bildirim icin; gercek fizik degil)
YATAY_MPS, DIKEY_MPS, DONUS_DPS = 5.0, 3.0, 45.0


def yerel_ip():
    """Varsayilan ag arayuzunun IP'si (paket gondermez; UDP connect yalnizca rota secer)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))
        return s.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        s.close()


class SanalDrone(RosArayuzu):
    """ROS'un yerine: parser + guvenlik + yurutme benzetimi."""

    def __init__(self, cozucu, hiz_katsayisi=1.0):
        self.cozucu = cozucu
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
            self.durum = Guvenlik.sonraki_durum(self.durum, hedef)
            self.cek.havada = self.durum.havada     # Faz 10'da telemetriden gelecek
            self._yolla(self.cek.ros_geri_bildirim('tamamlandi', f'{komut["komut"]} tamamlandı'))

    def acil_dur_yayinla(self):
        self.acil_nesli += 1
        if self._gorev:
            self._gorev.cancel()                    # yurutulen adimi kes: yerinde kal
            self._gorev = None
        print('  ACİL DUR', flush=True)

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
    drone = SanalDrone(KomutCozucu(llm=llm), hiz_katsayisi=args.hiz)
    token = args.token or os.environ.get('TELSIZ_TOKEN') or secrets.token_urlsafe(9)
    cekirdek = TelsizCekirdegi(drone, Ayarlar(token=token, baglanti_koparsa=args.koparsa))
    sunucu = TelsizSunucusu(cekirdek, args.host, args.port)
    drone.sunucu = sunucu
    gorev = asyncio.ensure_future(sunucu.calis())
    await sunucu.hazir_bekle()
    adres = protokol.baglanti_adresi(args.ilan_ip or yerel_ip(), sunucu.port, token)
    print(f'\nDeneme sunucusu (ROS yok). Bağlantı adresi:\n{adres}')
    print(f'LLM: {args.llm or "yok"} | Ctrl+C ile çık\n', flush=True)
    if hazir:
        hazir(sunucu, adres)
    await gorev


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
    return ap


def main(argv=None):
    args = arguman_cozucu().parse_args(argv)
    try:
        asyncio.run(calis(args))
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
