"""ROS ve PX4 OLMADAN telsiz koprusunu calistiran deneme sunucusu.

Faz 3: Gelen metni ekrana yazar ("yanki"). Faz 5'te bu metin drone
reposundaki gercek command_parser'dan gecirilecek.

    python3 -m mobile_bridge.deneme_sunucusu --token ABC
"""
import argparse
import asyncio
import os
import secrets
import socket

from . import protokol
from .cekirdek import Ayarlar, RosArayuzu, TelsizCekirdegi
from .sunucu import TelsizSunucusu


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


class YankiRos(RosArayuzu):
    """ROS yerine: yayinlanan metni ekrana yazar."""

    def __init__(self):
        self.metinler = []

    def metin_yayinla(self, metin):
        self.metinler.append(metin)
        print(f'  /voice/text <- "{metin}"', flush=True)


async def calis(args, hazir=None):
    token = args.token or os.environ.get('TELSIZ_TOKEN') or secrets.token_urlsafe(9)
    cekirdek = TelsizCekirdegi(YankiRos(), Ayarlar(token=token))
    sunucu = TelsizSunucusu(cekirdek, args.host, args.port)
    gorev = asyncio.ensure_future(sunucu.calis())
    await sunucu.hazir_bekle()
    adres = protokol.baglanti_adresi(args.ilan_ip or yerel_ip(), sunucu.port, token)
    print(f'\nDeneme sunucusu (ROS yok). Bağlantı adresi:\n{adres}\nCtrl+C ile çık\n', flush=True)
    if hazir:
        hazir(sunucu, adres)
    await gorev


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--host', default='0.0.0.0')
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--ilan-ip', default='', help='adreste gösterilecek IP (boş = otomatik)')
    ap.add_argument('--token', default='')
    args = ap.parse_args(argv)
    try:
        asyncio.run(calis(args))
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
