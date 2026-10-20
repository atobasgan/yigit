"""Telsiz protokolu (telefon <-> yer istasyonu), surum 1.

Tek WebSocket baglantisi (MOBIL_TELSIZ_UYGULAMASI.txt Bolum 9):
  - metin cercevesi = JSON kontrol mesaji, her mesajda "tip" alani
  - ikili cerceve   = ses parcasi: [uint32 id][uint32 sira][PCM16 LE mono]

ROS'tan bagimsizdir; telefon tarafindaki Dart kodu (mobil/lib/protokol/)
ayni kurallari uygular.
"""
import json
import struct

SURUM = 1
SES_BASLIGI = struct.Struct('<II')      # konusma id, parca sira no
ORNEKLEME_HZ = 16000
ORNEK_BAYT = 2                          # PCM16

# Telefon -> yer istasyonu
GELEN_TIPLER = {
    'merhaba': {'token': str},
    'ptt_basla': {'id': int},
    'ptt_bitti': {'id': int},
    'ptt_iptal': {'id': int},
    'metin': {'id': int, 'metin': str},
    'acil_dur': {},
    'ping': {},
}
ROLLER = ('operator', 'izleyici')


class ProtokolHatasi(ValueError):
    """Gecersiz mesaj. kod alani telefona 'hata' mesajinda doner."""

    def __init__(self, kod, mesaj):
        super().__init__(mesaj)
        self.kod = kod


def json_coz(ham):
    """Gelen metin cercevesini dogrular ve sozluk dondurur."""
    try:
        mesaj = json.loads(ham)
    except (TypeError, ValueError) as e:
        raise ProtokolHatasi('gecersiz_json', f'JSON çözülemedi: {e}') from e
    if not isinstance(mesaj, dict):
        raise ProtokolHatasi('gecersiz_json', 'mesaj bir nesne olmalı')
    tip = mesaj.get('tip')
    if tip not in GELEN_TIPLER:
        raise ProtokolHatasi('bilinmeyen_tip', f'bilinmeyen mesaj tipi: {tip!r}')
    for alan, tur in GELEN_TIPLER[tip].items():
        deger = mesaj.get(alan)
        # bool, int'in alt sinifi; id olarak kabul etme
        if not isinstance(deger, tur) or isinstance(deger, bool):
            raise ProtokolHatasi('eksik_alan', f'{tip}: "{alan}" alanı eksik ya da hatalı')
    if tip == 'merhaba':
        rol = mesaj.get('rol', 'operator')
        if rol not in ROLLER:
            raise ProtokolHatasi('eksik_alan', f'merhaba: geçersiz rol {rol!r}')
        mesaj['rol'] = rol
    return mesaj


def json_yaz(tip, **alanlar):
    """Giden kontrol mesajini olusturur (Turkce karakterler korunur)."""
    return json.dumps({'tip': tip, **alanlar}, ensure_ascii=False, separators=(',', ':'))


def ses_parcasi_coz(veri):
    """Ikili cerceveyi (id, sira, pcm_bayt) olarak ayirir."""
    if len(veri) < SES_BASLIGI.size:
        raise ProtokolHatasi('gecersiz_ses', 'ses parçası başlıktan kısa')
    konusma_id, sira = SES_BASLIGI.unpack_from(veri)
    pcm = bytes(veri[SES_BASLIGI.size:])
    if len(pcm) % ORNEK_BAYT:
        raise ProtokolHatasi('gecersiz_ses', 'PCM16 verisi tek sayıda bayt olamaz')
    return konusma_id, sira, pcm


def ses_parcasi_yaz(konusma_id, sira, pcm):
    """Test ve istemci icin: ikili ses cercevesi uretir."""
    return SES_BASLIGI.pack(konusma_id, sira) + bytes(pcm)


def baglanti_adresi(host, port, token, yol='/telsiz'):
    """QR koda konan adres: ws://host:port/telsiz?token=..."""
    return f'ws://{host}:{port}{yol}?token={token}'
