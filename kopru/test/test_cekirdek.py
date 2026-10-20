"""Cekirdek mantigi: sahte saat + sahte ROS ile (ag acilmaz)."""
import json
import struct

import pytest

from mobile_bridge import protokol as p
from mobile_bridge.cekirdek import HERKES, Ayarlar, RosArayuzu, TelsizCekirdegi


class SahteRos(RosArayuzu):
    def __init__(self):
        self.metinler, self.acil, self.konusmalar, self.stt = [], 0, [], []

    def metin_yayinla(self, metin):
        self.metinler.append(metin)

    def acil_dur_yayinla(self):
        self.acil += 1

    def konusma_yayinla(self, konusma, kaynak):
        self.konusmalar.append((konusma.konusma_id, kaynak))

    def stt_baslat(self, konusma):
        self.stt.append(konusma)


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
    return TelsizCekirdegi(ros, Ayarlar(token='gizli'), saat=saat, stt_hazir=True), ros, saat


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
    c.havada = False                             # (yerdeyken kopma dur gondermez)
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


def test_komut_bekleyen_konusmayla_eslesir(ortam):
    c, ros, saat = ortam
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('metin', id=7, metin='20 metre yüksel'))
    saat.t += 0.012
    k = mesaj(c.ros_komut({'metin': '20 m yüksel', 'kaynak': 'hizli_yol', 'kuyruga_ekle': False,
                           'adimlar': [{'komut': 'yuksel', 'metre': 20}], 'parser_ms': 0.1}), 'komut')
    assert k['id'] == 7 and k['gecikme_ms'] == 12 and k['adimlar'][0]['komut'] == 'yuksel'
    gb = mesaj(c.ros_geri_bildirim('yurutuyor', '20 metre yükseliyorum'), 'geri_bildirim')
    assert gb['id'] == 7, 'yürütücünün geri bildirimi son komutun kartına'


def test_sirali_iki_konusma(ortam):
    c, *_ = ortam
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('metin', id=1, metin='kalk'))
    c.metin_cercevesi(i, p.json_yaz('metin', id=2, metin='in'))
    assert mesaj(c.ros_komut({'adimlar': []}), 'komut')['id'] == 1
    assert mesaj(c.ros_komut({'adimlar': []}), 'komut')['id'] == 2


def test_anlamadim_bekleyen_konusmaya_baglanir(ortam):
    c, *_ = ortam
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('metin', id=3, metin='saat kaç'))
    assert mesaj(c.ros_geri_bildirim('reddedildi', 'anlamadım: "saat kaç"'), 'anlasilmadi')['id'] == 3


def test_eslestirme_zaman_asimi(ortam):
    c, ros, saat = ortam
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('metin', id=1, metin='kalk'))
    saat.t += 60
    assert mesaj(c.ros_komut({'adimlar': []}), 'komut')['id'] is None


# ---------------------------------------------------------------- Faz 6: guvenlik
def test_izleyici_de_acil_dur_verebilir(ortam):
    c, ros, _ = ortam
    giris(c, 'a')
    b, _ = giris(c, 'b', rol='izleyici')
    cikti = c.metin_cercevesi(b, p.json_yaz('acil_dur'))
    assert ros.acil == 1 and cikti[0][0] is HERKES
    assert mesaj(cikti, 'geri_bildirim')['durum'] == 'acil_dur'


def test_kalp_atisi_kesilince_dur(ortam):
    c, ros, saat = ortam
    i, _ = giris(c)
    saat.t += 2
    assert c.tik() == []
    c.metin_cercevesi(i, p.json_yaz('ping', t=1))      # sinyal geldi, sayac sifirlandi
    saat.t += 3.5
    cikti = c.tik()
    assert ros.acil == 1 and mesaj(cikti, 'geri_bildirim')['durum'] == 'telsiz_koptu'
    saat.t += 5
    assert c.tik() == [] and ros.acil == 1             # bir kopma = bir dur


def test_baglanti_kapaninca_dur(ortam):
    c, ros, _ = ortam
    i, _ = giris(c)
    assert 'asılı kalıyor' in mesaj(c.koptu(i), 'geri_bildirim')['mesaj'] and ros.acil == 1


def test_yerdeyken_kopma_dur_gondermez(ortam):
    c, ros, _ = ortam
    i, _ = giris(c)
    c.havada = False
    c.koptu(i)
    assert ros.acil == 0


def test_devam_ayari_ve_yeniden_baglanma(ortam):
    c, ros, _ = ortam
    c.ayarlar.baglanti_koparsa = 'devam'
    i, _ = giris(c)
    assert 'devam' in mesaj(c.koptu(i), 'geri_bildirim')['mesaj'] and ros.acil == 0
    _, cikti = giris(c, 'yeni')
    assert mesaj(cikti, 'hos_geldin')['rol'] == 'operator'


def test_iptal_edilen_sonuc_bekleyen_karta_reddedildi_olur(ortam):
    c, *_ = ortam
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('metin', id=9, metin='önce on metre yüksel sonra doğuya git'))
    gb = mesaj(c.ros_geri_bildirim('iptal', 'ACİL DUR geldiği için "..." iptal edildi'), 'geri_bildirim')
    assert gb['id'] == 9 and gb['durum'] == 'reddedildi'


# ---------------------------------------------------------------- Faz 8: ses
def ses(c, i, kid, sure_s, parca=640):
    pcm = struct.pack('<h', 1000) * int(16000 * sure_s)
    for n, k in enumerate(range(0, len(pcm), parca)):
        c.ikili_cerceve(i, p.ses_parcasi_yaz(kid, n, pcm[k:k + parca]))


def test_bas_konus_sesi_birlesir_ve_stt_ye_gider(ortam):
    c, ros, _ = ortam
    i, cikti = giris(c)
    assert mesaj(cikti, 'hos_geldin')['yer_stt'] is True
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=5))
    ses(c, i, 5, 1.0)
    isl = mesaj(c.metin_cercevesi(i, p.json_yaz('ptt_bitti', id=5)), 'isleniyor')
    assert isl['sure_ms'] == 1000 and isl['kayip_parca'] == 0
    assert ros.konusmalar == [(5, 'telefon')] and len(ros.stt) == 1
    assert len(ros.stt[0].pcm()) == 32000                     # 1 sn x 16000 x 2 bayt
    cikti = c.stt_sonucu(ros.stt[0], '20 metre yüksel', 230.4)
    assert mesaj(cikti, 'duyuldu')['stt_ms'] == 230 and ros.metinler == ['20 metre yüksel']
    assert mesaj(cikti, 'duyuldu')['kaynak'] == 'yer_stt'


def test_parcalar_sirasiz_gelse_de_birlesir(ortam):
    c, ros, _ = ortam
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=1))
    a, b = struct.pack('<h', 1) * 4000, struct.pack('<h', 2) * 4000
    c.ikili_cerceve(i, p.ses_parcasi_yaz(1, 1, b))            # 2. parca once geldi
    c.ikili_cerceve(i, p.ses_parcasi_yaz(1, 0, a))
    c.ikili_cerceve(i, p.ses_parcasi_yaz(1, 1, b))            # tekrar gelen parca
    c.metin_cercevesi(i, p.json_yaz('ptt_bitti', id=1))
    assert ros.stt[0].pcm() == a + b


def test_kisa_uzun_iptal_ve_eski_parca(ortam):
    c, ros, _ = ortam
    c.ayarlar.en_uzun_konusma_s = 1.0
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=1))
    ses(c, i, 1, 0.1)
    cikti = c.metin_cercevesi(i, p.json_yaz('ptt_bitti', id=1))
    assert 'çok kısa' in mesaj(cikti, 'anlasilmadi')['sebep']
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=2))
    hata = c.ikili_cerceve(i, p.ses_parcasi_yaz(2, 0, b'\x00\x00' * 17000))
    assert mesaj(hata, 'hata')['kod'] == 'konusma_cok_uzun'
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=3))
    c.metin_cercevesi(i, p.json_yaz('ptt_iptal', id=3))
    assert c.ikili_cerceve(i, p.ses_parcasi_yaz(3, 0, b'\x00\x00')) == []
    assert mesaj(c.metin_cercevesi(i, p.json_yaz('ptt_bitti', id=3)), 'hata')['kod'] == 'konusma_yok'
    assert ros.stt == []


def test_izleyicinin_sesi_alinmaz(ortam):
    c, ros, _ = ortam
    giris(c, 'a')
    b, _ = giris(c, 'b', rol='izleyici')
    assert c.ikili_cerceve(b, p.ses_parcasi_yaz(1, 0, b'\x00\x00')) == []


def test_yer_stt_yoksa_bilgilendirir():
    ros = SahteRos()
    c = TelsizCekirdegi(ros, Ayarlar(token='gizli'), saat=Saat(), stt_hazir=False)
    i, cikti = giris(c)
    assert mesaj(cikti, 'hos_geldin')['yer_stt'] is False
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=1))
    ses(c, i, 1, 0.5)
    sebep = mesaj(c.metin_cercevesi(i, p.json_yaz('ptt_bitti', id=1)), 'anlasilmadi')['sebep']
    assert 'telefonda tanı' in sebep and ros.stt == []


# ---------------------------------------------------------------- Faz 9: kayit
def test_konusma_wav_ve_etiket_olarak_kaydedilir(tmp_path):
    ros = SahteRos()
    c = TelsizCekirdegi(ros, Ayarlar(token='gizli', kayit_klasoru=str(tmp_path)), saat=Saat(),
                        stt_hazir=True)
    i, _ = giris(c)
    c.metin_cercevesi(i, p.json_yaz('ptt_basla', id=5))
    ses(c, i, 5, 1.0)
    c.metin_cercevesi(i, p.json_yaz('ptt_bitti', id=5))
    c.stt_sonucu(ros.stt[0], 'yirmi metre; yüksel', 200)
    wavlar = list(tmp_path.glob('*.wav'))
    assert len(wavlar) == 1 and wavlar[0].name.endswith('_00005.wav')
    from mobile_bridge.ses import wav_oku
    pcm, hz = wav_oku(str(wavlar[0]))
    assert hz == 16000 and len(pcm) == 32000
    satirlar = (tmp_path / 'etiketler.csv').read_text(encoding='utf-8').splitlines()
    assert satirlar == ['dosya;stt_metni;beklenen_metin', f'{wavlar[0].name};yirmi metre, yüksel;']
