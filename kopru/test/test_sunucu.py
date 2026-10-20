"""Gercek WebSocket sunucusu + sahte_telefon istemcisi (uctan uca, ROS'suz)."""
import asyncio
import struct
import wave

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

    def stt_baslat(self, konusma):
        # baska thread'deki STT bitmis gibi: sonucu disaridan() ile donguye ver
        self.sunucu.disaridan(self.sunucu.cekirdek.stt_sonucu, konusma, 'kalk', 5.0)


async def sunucuyla(senaryo):
    ros = SahteRos()
    sunucu = TelsizSunucusu(TelsizCekirdegi(ros, Ayarlar(token='T'), stt_hazir=True), '127.0.0.1', 0)
    ros.sunucu = sunucu
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


def test_wav_bas_konus_uctan_uca(tmp_path):
    yol = tmp_path / 'k.wav'
    with wave.open(str(yol), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(struct.pack('<h', 500) * 16000)
    satirlar = []

    async def senaryo(port):
        await sahte_telefon.calistir(f'ws://127.0.0.1:{port}/telsiz?token=T', wav=str(yol),
                                     gercek_zaman=False, bekle_s=0.3, cikti=satirlar.append)
    ros, _ = asyncio.run(sunucuyla(senaryo))
    log = '\n'.join(satirlar)
    assert '"tip": "isleniyor"' in log and '"sure_ms": 1000' in log
    assert ros.metinler == ['kalk'] and '"kaynak": "yer_stt"' in log
