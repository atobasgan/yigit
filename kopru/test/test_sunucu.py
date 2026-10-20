"""Gercek WebSocket sunucusu + sahte_telefon istemcisi (uctan uca, ROS'suz)."""
import asyncio

import websockets

from mobile_bridge import sahte_telefon
from mobile_bridge.cekirdek import Ayarlar, RosArayuzu, TelsizCekirdegi
from mobile_bridge.sunucu import TelsizSunucusu


class SahteRos(RosArayuzu):
    def __init__(self):
        self.metinler, self.acil = [], 0

    def metin_yayinla(self, metin):
        self.metinler.append(metin)

    def acil_dur_yayinla(self):
        self.acil += 1


async def sunucuyla(senaryo):
    ros = SahteRos()
    sunucu = TelsizSunucusu(TelsizCekirdegi(ros, Ayarlar(token='T')), '127.0.0.1', 0)
    gorev = asyncio.ensure_future(sunucu.calis())
    await sunucu.hazir_bekle()                   # port 0 -> isletim sistemi bos port verir
    try:
        sonuc = await senaryo(sunucu.port)
    finally:
        sunucu.durdur()
        await gorev
    return ros, sonuc


def test_metin_uctan_uca():
    satirlar = []

    async def senaryo(port):
        await sahte_telefon.calistir(f'ws://127.0.0.1:{port}/telsiz?token=T', metin='kalk',
                                     bekle_s=0.3, cikti=satirlar.append)
    ros, _ = asyncio.run(sunucuyla(senaryo))
    assert ros.metinler == ['kalk']
    log = '\n'.join(satirlar)
    assert "'rol': 'operator'" in log and '"tip": "duyuldu"' in log


def test_yanlis_yol_reddedilir():
    async def senaryo(port):
        async with websockets.connect(f'ws://127.0.0.1:{port}/baska') as ws:
            try:
                await ws.recv()
            except websockets.ConnectionClosed as e:
                return e.rcvd.code
    _, kod = asyncio.run(sunucuyla(senaryo))
    assert kod == 4404


def test_acil_dur_uctan_uca():
    satirlar = []

    async def senaryo(port):
        await sahte_telefon.calistir(f'ws://127.0.0.1:{port}/telsiz?token=T', acil=True,
                                     bekle_s=0.3, cikti=satirlar.append)
    ros, _ = asyncio.run(sunucuyla(senaryo))
    # 1: ACIL DUR tusu, 2: operator baglantiyi kapatti (drone havada olabilir -> guvenli taraf)
    assert ros.acil == 2 and 'acil_dur' in '\n'.join(satirlar)
