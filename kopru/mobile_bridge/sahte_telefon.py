"""Telefon olmadan telsiz koprusunu denemek icin komut satiri istemcisi.

Telefon uygulamasiyla ayni protokolu konusur (protokol.py):

    python3 -m mobile_bridge.sahte_telefon --url 'ws://127.0.0.1:8765/telsiz?token=XYZ' \\
        --metin "önce 20 metre yüksel sonra kuzeye 50 metre git"
"""
import argparse
import asyncio
import json
import sys
import time
from urllib.parse import parse_qs, urlparse

import websockets

from . import protokol as p


def adres_coz(url):
    """'ws://h:p/telsiz?token=T' -> ('ws://h:p/telsiz', 'T')"""
    u = urlparse(url)
    token = parse_qs(u.query).get('token', [''])[0]
    return u._replace(query='').geturl(), token


async def calistir(url, metin=None, bekle_s=4.0, cikti=print, rol='operator'):
    adres, token = adres_coz(url)
    async with websockets.connect(adres, max_size=1 << 20) as ws:
        await ws.send(p.json_yaz('merhaba', surum=p.SURUM, token=token, rol=rol,
                                 cihaz='sahte_telefon'))
        hos = json.loads(await ws.recv())
        cikti(f'<- {hos}')
        if hos.get('tip') != 'hos_geldin':
            return 1
        konusma_id = int(time.time()) % 100000
        t0 = time.perf_counter()
        if metin is not None:
            await ws.send(p.json_yaz('metin', id=konusma_id, metin=metin, kaynak='klavye'))

        son = time.perf_counter() + bekle_s
        while time.perf_counter() < son:
            try:
                ham = await asyncio.wait_for(ws.recv(), timeout=son - time.perf_counter())
            except asyncio.TimeoutError:
                break
            mesaj = json.loads(ham)
            ms = (time.perf_counter() - t0) * 1000
            cikti(f'<- +{ms:6.0f} ms {json.dumps(mesaj, ensure_ascii=False)}')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--url', required=True, help="ws://IP:8765/telsiz?token=...")
    ap.add_argument('--metin', required=True)
    ap.add_argument('--bekle', type=float, default=2.0, help='cevaplari kaç saniye dinle')
    args = ap.parse_args(argv)
    return asyncio.run(calistir(args.url, args.metin, args.bekle))


if __name__ == '__main__':
    sys.exit(main())
