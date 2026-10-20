"""Cekirdek mantigi: sahte saat + sahte ROS ile (ag acilmaz)."""
import json

import pytest

from mobile_bridge import protokol as p
from mobile_bridge.cekirdek import HERKES, Ayarlar, RosArayuzu, TelsizCekirdegi


class SahteRos(RosArayuzu):
    def __init__(self):
        self.metinler = []

    def metin_yayinla(self, metin):
        self.metinler.append(metin)


class Saat:
    def __init__(self):
        self.t = 100.0

    def __call__(self):
        return self.t


def mesaj(cikti, tip):
    return next(json.loads(m) for _, m in cikti if json.loads(m)['tip'] == tip)


@pytest.fixture
def ortam():
    ros, saat = SahteRos(), Saat()
    return TelsizCekirdegi(ros, Ayarlar(token='gizli'), saat=saat), ros, saat


def giris(c, ad='tel', rol='operator', token='gizli'):
    i = c.baglandi(ad)
    return i, c.metin_cercevesi(i, p.json_yaz('merhaba', token=token, rol=rol, cihaz=ad))


def test_token_hatali_ise_yetkisiz(ortam):
    c, ros, _ = ortam
    i, cikti = giris(c, token='yanlis')
    assert mesaj(cikti, 'hata')['kod'] == 'yetkisiz'
    assert mesaj(c.metin_cercevesi(i, p.json_yaz('metin', id=1, metin='kalk')), 'hata')['kod'] == 'yetkisiz'
    assert ros.metinler == []


def test_bozuk_mesaj_cokertmez(ortam):
    c, *_ = ortam
    i, _ = giris(c)
    assert mesaj(c.metin_cercevesi(i, 'bozuk{'), 'hata')['kod'] == 'gecersiz_json'


def test_tek_operator(ortam):
    c, *_ = ortam
    a, cikti = giris(c, 'a')
    assert mesaj(cikti, 'hos_geldin')['rol'] == 'operator'
    b, cikti = giris(c, 'b')
    assert mesaj(cikti, 'hos_geldin')['rol'] == 'izleyici'
    assert mesaj(cikti, 'hata')['kod'] == 'operator_dolu'
    assert mesaj(c.metin_cercevesi(b, p.json_yaz('metin', id=1, metin='kalk')), 'hata')['kod'] \
        == 'operator_degil'
    c.koptu(a)                                   # operator ayrilinca yer bosalir
    _, cikti = giris(c, 'c')
    assert mesaj(cikti, 'hos_geldin')['rol'] == 'operator'


def test_metin_yayinlanir_ve_herkese_duyurulur(ortam):
    c, ros, _ = ortam
    i, _ = giris(c)
    cikti = c.metin_cercevesi(i, p.json_yaz('metin', id=7, metin=' 20 metre yüksel '))
    assert ros.metinler == ['20 metre yüksel']
    alici, _ = cikti[0]
    assert alici is HERKES
    assert mesaj(cikti, 'duyuldu') == {'tip': 'duyuldu', 'id': 7, 'metin': '20 metre yüksel',
                                       'kaynak': 'klavye', 'stt_ms': None}


def test_ping_pong(ortam):
    c, *_ = ortam
    i, _ = giris(c)
    assert mesaj(c.metin_cercevesi(i, p.json_yaz('ping', t=123)), 'pong')['t'] == 123


def test_henuz_olmayan_mesaj(ortam):
    c, *_ = ortam
    i, _ = giris(c)
    assert mesaj(c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=1)), 'hata')['kod'] == 'desteklenmiyor'
