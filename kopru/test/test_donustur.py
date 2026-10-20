from types import SimpleNamespace as NS

from mobile_bridge.donustur import adim_sozlugu, komut_listesi_sozlugu


def adim(**kw):
    taban = dict(komut='', metre=0.0, derece=0.0, yon='', enlem=0.0, boylam=0.0, tur='',
                 saniye=0.0, mps=0.0)
    return NS(**{**taban, **kw})


def test_adimlar_sema_bicimine_doner():
    assert adim_sozlugu(adim(komut='kalk')) == {'komut': 'kalk'}
    assert adim_sozlugu(adim(komut='kalk', metre=10.0)) == {'komut': 'kalk', 'irtifa_m': 10}
    assert adim_sozlugu(adim(komut='git_yon', yon='kuzey', metre=50.0)) == \
        {'komut': 'git_yon', 'yon': 'kuzey', 'metre': 50}
    assert adim_sozlugu(adim(komut='alcal', metre=1.5)) == {'komut': 'alcal', 'metre': 1.5}
    assert adim_sozlugu(adim(komut='dur', metre=3.0)) == {'komut': 'dur'}


def test_komut_listesi():
    t1, t2 = NS(sec=10, nanosec=0), NS(sec=10, nanosec=2_500_000)
    msg = NS(metin='20 m yüksel', kaynak='hizli_yol', kuyruga_ekle=False,
             adimlar=[adim(komut='yuksel', metre=20.0)], t_metin_geldi=t1, t_komut_hazir=t2)
    s = komut_listesi_sozlugu(msg)
    assert s['adimlar'] == [{'komut': 'yuksel', 'metre': 20}] and s['parser_ms'] == 2.5
