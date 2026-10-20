import pytest

from mobile_bridge import protokol as p


def test_merhaba_varsayilan_rol():
    m = p.json_coz('{"tip":"merhaba","token":"abc"}')
    assert m['rol'] == 'operator'


@pytest.mark.parametrize('ham,kod', [
    ('bozuk', 'gecersiz_json'),
    ('[1,2]', 'gecersiz_json'),
    ('{"tip":"uc"}', 'bilinmeyen_tip'),
    ('{"tip":"merhaba"}', 'eksik_alan'),
    ('{"tip":"ptt_basla","id":"7"}', 'eksik_alan'),
    ('{"tip":"ptt_basla","id":true}', 'eksik_alan'),
    ('{"tip":"metin","id":1}', 'eksik_alan'),
    ('{"tip":"merhaba","token":"x","rol":"kaptan"}', 'eksik_alan'),
])
def test_gecersiz_mesajlar(ham, kod):
    with pytest.raises(p.ProtokolHatasi) as e:
        p.json_coz(ham)
    assert e.value.kod == kod


def test_json_yaz_turkce_korunur():
    assert p.json_yaz('duyuldu', metin='yüksel') == '{"tip":"duyuldu","metin":"yüksel"}'


def test_ses_parcasi_gidis_donus():
    veri = p.ses_parcasi_yaz(42, 7, b'\x01\x00\x02\x00')
    assert len(veri) == 8 + 4
    assert p.ses_parcasi_coz(veri) == (42, 7, b'\x01\x00\x02\x00')


def test_ses_parcasi_hatalari():
    with pytest.raises(p.ProtokolHatasi):
        p.ses_parcasi_coz(b'\x00\x01')
    with pytest.raises(p.ProtokolHatasi):
        p.ses_parcasi_coz(p.ses_parcasi_yaz(1, 0, b'\x01'))


def test_baglanti_adresi():
    assert p.baglanti_adresi('192.168.1.5', 8765, 'T') == 'ws://192.168.1.5:8765/telsiz?token=T'


def test_ortak_test_vektoru():
    """Dart tarafinda (mobil/test/protokol_test.dart) da ayni bayt dizisi."""
    assert list(p.ses_parcasi_yaz(0x01020304, 7, bytes([9, 8]))) == [4, 3, 2, 1, 7, 0, 0, 0, 9, 8]
