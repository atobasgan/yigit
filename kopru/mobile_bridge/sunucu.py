"""asyncio + websockets ile telsiz sunucusu.

Cekirdek (TelsizCekirdegi) YALNIZCA bu sunucunun olay dongusu thread'inde
calisir. Baska thread'lerden (ROS callback'leri, STT isci thread'i) gelen
olaylar disaridan() ile donguye aktarilir; boylece kilit gerekmez.
"""
import asyncio
import logging
from urllib.parse import urlparse

import websockets

from .cekirdek import HERKES

log = logging.getLogger('mobile_bridge')


class TelsizSunucusu:

    def __init__(self, cekirdek, host='0.0.0.0', port=8765, yol='/telsiz', tik_s=0.5):
        self.cekirdek = cekirdek
        self.host = host
        self.port = port
        self.yol = yol
        self.tik_s = tik_s
        self._baglantilar = {}          # Istemci -> websocket
        self._dongu = None
        self._hazir = asyncio.Event()
        self._durdur = None

    # ------------------------------------------------------------------ disaridan
    def disaridan(self, fonksiyon, *args):
        """Thread-guvenli: cekirdek.fonksiyon(*args)'i dongude calistirir, ciktiyi gonderir."""
        if self._dongu is None or self._dongu.is_closed():
            return
        self._dongu.call_soon_threadsafe(
            lambda: asyncio.ensure_future(self._gonder(fonksiyon(*args))))

    # ------------------------------------------------------------------ calistirma
    async def calis(self):
        self._dongu = asyncio.get_running_loop()
        self._durdur = asyncio.Event()
        async with websockets.serve(
                self._baglanti, self.host, self.port,
                max_size=1 << 20,               # tek cerceve en fazla 1 MB
                compression=None,               # ses zaten sikistirilamaz; gecikme ekler
                ping_interval=5, ping_timeout=5) as sunucu:
            if self.port == 0:                  # testlerde rastgele port
                self.port = next(iter(sunucu.sockets)).getsockname()[1]
            self._hazir.set()
            tik = asyncio.ensure_future(self._tik_dongusu())
            await self._durdur.wait()
            tik.cancel()

    def durdur(self):
        if self._dongu and self._durdur:
            self._dongu.call_soon_threadsafe(self._durdur.set)

    async def hazir_bekle(self):
        await self._hazir.wait()

    async def _tik_dongusu(self):
        while True:
            await asyncio.sleep(self.tik_s)
            await self._gonder(self.cekirdek.tik())

    # ------------------------------------------------------------------ baglanti
    async def _baglanti(self, ws):
        yol = urlparse(ws.request.path).path if ws.request else ''
        if yol.rstrip('/') != self.yol:
            await ws.close(code=4404, reason='yol bulunamadi')
            return
        adres = '%s:%s' % ws.remote_address[:2] if ws.remote_address else '?'
        istemci = self.cekirdek.baglandi(adres)
        self._baglantilar[istemci] = ws
        log.info('baglandi: %s', adres)
        try:
            async for veri in ws:
                if isinstance(veri, (bytes, bytearray)):
                    cikti = self.cekirdek.ikili_cerceve(istemci, veri)
                else:
                    cikti = self.cekirdek.metin_cercevesi(istemci, veri)
                await self._gonder(cikti)
        except websockets.ConnectionClosed:
            pass
        finally:
            self._baglantilar.pop(istemci, None)
            log.info('ayrildi: %s', adres)
            await self._gonder(self.cekirdek.koptu(istemci))

    async def _gonder(self, cikti):
        for alici, mesaj in cikti or ():
            if alici is HERKES:
                hedefler = [ws for i, ws in self._baglantilar.items() if i.dogrulandi]
            else:
                ws = self._baglantilar.get(alici)
                hedefler = [ws] if ws else []
            for ws in hedefler:
                try:
                    await ws.send(mesaj)
                except websockets.ConnectionClosed:
                    pass
