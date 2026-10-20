"""ROS mesajlarini telefona gidecek sade sozluklere cevirir (ROS'suz test edilir).

Komutlar telefona LLM ile AYNI JSON semasinda gosterilir (command_parser/schema.py):
    DroneCommand(komut='kalk', metre=10.0)  ->  {"komut": "kalk", "irtifa_m": 10.0}
Boylece operator ekranda hizli yolun ya da LLM'in tam olarak ne urettigini gorur.
"""
import math

try:
    from command_parser.schema import KOMUTLAR
except ImportError:                     # command_parser kurulu degilse ayni tablo
    KOMUTLAR = {
        'kalk': ((), ('irtifa_m',)), 'in': ((), ()), 'yuksel': (('metre',), ()),
        'alcal': (('metre',), ()), 'irtifaya_cik': (('metre',), ()),
        'git_yon': (('yon', 'metre'), ()), 'don': (('yon', 'derece'), ()),
        'git_koordinat': (('enlem', 'boylam'), ('irtifa_m',)),
        'yakin_yere_git': (('tur',), ()), 'bekle': (('saniye',), ()),
        'hiz_ayarla': (('mps',), ()), 'eve_don': ((), ()), 'dur': ((), ()),
        'bilinmiyor': ((), ()),
    }

# PX4 VehicleStatus.nav_state -> okunur ad (en sik olanlar)
NAV_DURUMLARI = {
    0: 'MANUEL', 1: 'İRTİFA', 2: 'KONUM', 3: 'GÖREV', 4: 'BEKLE (HOLD)', 5: 'EVE DÖNÜŞ',
    14: 'OFFBOARD', 15: 'STABİLİZE', 17: 'KALKIŞ', 18: 'İNİŞ', 19: 'TAKİP',
}


def _yuvarla(deger):
    deger = float(deger)
    return int(deger) if deger.is_integer() else round(deger, 6)


def adim_sozlugu(adim):
    """DroneCommand (ya da ayni alanli nesne) -> sema bicimli sozluk."""
    ad = adim.komut
    zorunlu, istege_bagli = KOMUTLAR.get(ad, ((), ()))
    sonuc = {'komut': ad}
    for alan in zorunlu + istege_bagli:
        kaynak = 'metre' if alan == 'irtifa_m' else alan
        deger = getattr(adim, kaynak, None)
        if isinstance(deger, str):
            if deger:
                sonuc[alan] = deger
        elif deger is not None and (alan in zorunlu or deger):
            sonuc[alan] = _yuvarla(deger)
    return sonuc


def _zaman_s(t):
    return t.sec + t.nanosec / 1e9


def komut_listesi_sozlugu(msg):
    """CommandList -> {'metin','kaynak','kuyruga_ekle','adimlar','parser_ms'}"""
    parser_ms = None
    if msg.t_metin_geldi.sec and msg.t_komut_hazir.sec:
        parser_ms = round((_zaman_s(msg.t_komut_hazir) - _zaman_s(msg.t_metin_geldi)) * 1000, 1)
    return {
        'metin': msg.metin,
        'kaynak': msg.kaynak,
        'kuyruga_ekle': bool(msg.kuyruga_ekle),
        'adimlar': [adim_sozlugu(a) for a in msg.adimlar],
        'parser_ms': parser_ms,
    }


def telemetri_sozlugu(px4):
    """mission_executor.px4_interface.PX4Arayuz -> telefona giden ozet (2 Hz)."""
    if not px4.hazir:
        return {'hazir': False}
    poz = px4.poz()
    g = px4.global_
    durum = px4.durum
    veri = {
        'hazir': True,
        'irtifa': round(poz.irtifa, 1),
        'hiz': round(px4.hiz(), 1),
        'yaw': round(math.degrees(poz.yaw) % 360, 0),
        'x': round(poz.x, 1),
        'y': round(poz.y, 1),
        'batarya': round(px4.batarya_orani, 2),
        'arm': px4.armli,
        'havada': px4.havada,
        'mod': NAV_DURUMLARI.get(durum.nav_state, str(durum.nav_state)) if durum else '?',
    }
    if g is not None:
        veri['enlem'] = round(g.lat, 6)
        veri['boylam'] = round(g.lon, 6)
    return veri
