"""Telefon olmadan telsiz koprusunu denemek icin komut satiri istemcisi.

Telefon uygulamasiyla ayni protokolu konusur (protokol.py):

    python3 -m mobile_bridge.sahte_telefon --url 'ws://127.0.0.1:8765/telsiz?token=XYZ' \\
        --metin "önce 20 metre yüksel sonra kuzeye 50 metre git"
    python3 -m mobile_bridge.sahte_telefon --url ... --acil --izleyici
    python3 -m mobile_bridge.sahte_telefon --url ... --wav kayit.wav

--wav: dosya 20 ms'lik parcalar halinde GERCEK ZAMANLI akitilir (bas-konus
tusuna basili tutuluyormus gibi); tus birakma ani = son parca.
"""
import argparse
import asyncio
import json
import sys
import time
from urllib.parse import parse_qs, urlparse

import websockets

from . import protokol as p
from .ses import wav_oku

PARCA_BAYT = p.ORNEKLEME_HZ * p.ORNEK_BAYT // 50     # 20 ms = 640 bayt


def adres_coz(url):
    """'ws://h:p/telsiz?token=T' -> ('ws://h:p/telsiz', 'T')"""
    u = urlparse(url)
    token = parse_qs(u.query).get('token', [''])[0]
    return u._replace(query='').geturl(), token


async def calistir(url, metin=None, acil=False, bekle_s=4.0, cikti=print, rol='operator',
                   wav=None, gercek_zaman=True, telemetri_goster=False):
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
        if acil:
            await ws.send(p.json_yaz('acil_dur'))
        elif metin is not None:
            await ws.send(p.json_yaz('metin', id=konusma_id, metin=metin, kaynak='klavye'))
        elif wav is not None:
            pcm, hz = wav_oku(wav)
            if hz != p.ORNEKLEME_HZ:
                cikti(f'uyarı: {hz} Hz; 16000 Hz bekleniyor')
            await ws.send(p.json_yaz('ptt_basla', id=konusma_id))
            sira = -1
            for sira, i in enumerate(range(0, len(pcm), PARCA_BAYT)):
                await ws.send(p.ses_parcasi_yaz(konusma_id, sira, pcm[i:i + PARCA_BAYT]))
                if gercek_zaman:
                    await asyncio.sleep(0.02)
            t0 = time.perf_counter()          # "tus birakildi"
            await ws.send(p.json_yaz('ptt_bitti', id=konusma_id, parca_sayisi=sira + 1))

        son = time.perf_counter() + bekle_s
        while time.perf_counter() < son:
            try:
                ham = await asyncio.wait_for(ws.recv(), timeout=son - time.perf_counter())
            except asyncio.TimeoutError:
                break
            mesaj = json.loads(ham)
            if mesaj.get('tip') == 'telemetri' and not telemetri_goster:
                continue                      # 2 Hz akar; okumayi zorlastirmasin
            ms = (time.perf_counter() - t0) * 1000
            cikti(f'<- +{ms:6.0f} ms {json.dumps(mesaj, ensure_ascii=False)}')
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--url', required=True, help="ws://IP:8765/telsiz?token=...")
    grup = ap.add_mutually_exclusive_group(required=True)
    grup.add_argument('--metin')
    grup.add_argument('--acil', action='store_true', help='ACİL DUR gönder')
    grup.add_argument('--wav', help='16 kHz mono WAV dosyasını bas-konuş gibi akıt')
    ap.add_argument('--izleyici', action='store_true', help='izleyici olarak bağlan')
    ap.add_argument('--telemetri', action='store_true', help='telemetri mesajlarını da yazdır')
    ap.add_argument('--bekle', type=float, default=2.0, help='cevaplari kaç saniye dinle')
    args = ap.parse_args(argv)
    return asyncio.run(calistir(args.url, args.metin, args.acil, args.bekle,
                                rol='izleyici' if args.izleyici else 'operator', wav=args.wav,
                                telemetri_goster=args.telemetri))


if __name__ == '__main__':
    sys.exit(main())
