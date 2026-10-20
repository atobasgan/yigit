"""ROS'suz deneme sunucusu: drone reposunun GERCEK parser'i + guvenlik + sanal drone."""
import asyncio
import json

import pytest
import websockets

from mobile_bridge import protokol as p
from mobile_bridge.drone_yolu import yolu_ekle

pytestmark = pytest.mark.skipif(not yolu_ekle(), reason='drone reposu yok (DRONE_REPO)')


def senaryo(adimlar, cozucu=None):
    from command_parser.komut_cozucu import KomutCozucu
    from mobile_bridge.cekirdek import Ayarlar, TelsizCekirdegi
    from mobile_bridge.deneme_sunucusu import SanalDrone
    from mobile_bridge.sunucu import TelsizSunucusu

    drone = SanalDrone(cozucu or KomutCozucu(), hiz_katsayisi=100)
    sunucu = TelsizSunucusu(TelsizCekirdegi(drone, Ayarlar(token='T')), '127.0.0.1', 0)
    drone.sunucu = sunucu
    gelen = []

    async def calis():
        g = asyncio.ensure_future(sunucu.calis())
        await sunucu.hazir_bekle()
        async with websockets.connect(f'ws://127.0.0.1:{sunucu.port}/telsiz') as ws:
            await ws.send(p.json_yaz('merhaba', token='T'))

            async def dinle():
                async for ham in ws:
                    gelen.append(json.loads(ham))
            d = asyncio.ensure_future(dinle())
            for adim in adimlar:
                if isinstance(adim, float):
                    await asyncio.sleep(adim)
                else:
                    await ws.send(adim)
            await asyncio.sleep(0.6)
            d.cancel()
        sunucu.durdur()
        await g

    asyncio.run(calis())
    return drone, gelen


def tipte(gelen, tip, **kosul):
    return [m for m in gelen if m['tip'] == tip and all(m.get(k) == v for k, v in kosul.items())]


def test_gercek_parser_json_ve_guvenlik():
    drone, gelen = senaryo([p.json_yaz('metin', id=1, metin='kalk'), 0.3,
                            p.json_yaz('metin', id=2, metin='beş yüz metre yüksel'), 0.2,
                            p.json_yaz('metin', id=3, metin='bugün hava nasıl')])
    kalk = tipte(gelen, 'komut', id=1)[0]
    assert kalk['adimlar'] == [{'komut': 'kalk'}] and kalk['kaynak'] == 'hizli_yol'
    assert tipte(gelen, 'geri_bildirim', id=1, durum='tamamlandi')
    assert tipte(gelen, 'komut', id=2)[0]['adimlar'] == [{'komut': 'yuksel', 'metre': 500.0}]
    red = tipte(gelen, 'geri_bildirim', id=2, durum='reddedildi')
    assert red and 'sınır' in red[0]['mesaj']
    assert tipte(gelen, 'anlasilmadi', id=3)
    assert drone.durum.havada and abs(drone.durum.poz.irtifa - 10) < 1e-6


def test_cozulurken_acil_dur_sonucu_iptal_eder():
    """LLM saniyelerce dusunurken ACIL DUR basilirsa gecikmeli sonuc yurutulmemeli."""
    import time

    from command_parser.komut_cozucu import KomutCozucu

    class YavasCozucu(KomutCozucu):           # LLM'i taklit: 'yavaş' iceren cumle 0.5 sn surer
        def coz(self, ham_metin):
            if 'yavaş' in ham_metin:
                time.sleep(0.5)
                return super().coz('10 metre yüksel')
            return super().coz(ham_metin)

    drone, gelen = senaryo([p.json_yaz('metin', id=1, metin='kalk'), 0.3,
                            p.json_yaz('metin', id=2, metin='yavaş yavaş biraz yüksel'), 0.1,
                            p.json_yaz('acil_dur')], cozucu=YavasCozucu())
    assert not tipte(gelen, 'komut', id=2), 'iptal edilen komut yayınlanmamalı'
    iptal = tipte(gelen, 'geri_bildirim', id=2, durum='reddedildi')
    assert iptal and 'ACİL DUR' in iptal[0]['mesaj']
    assert abs(drone.durum.poz.irtifa - 10) < 1e-6, 'drone yükselmemeli'
