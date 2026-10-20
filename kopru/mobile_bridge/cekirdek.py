"""Telsiz koprusunun cekirdegi: oturum, yetki, mesaj isleme.

ROS'tan ve agdan bagimsizdir. Her olay (mesaj geldi, baglanti koptu...) bir
metotla cekirdege verilir; cekirdek telefonlara gidecek mesajlari
[(alici, metin), ...] olarak DONDURUR ve ROS tarafindaki isleri RosArayuzu
uzerinden yapar. Boylece tum mantik ag acmadan, sahte bir ROS ile birim test
edilebilir (test/test_cekirdek.py). Faz 3: giris, roller, ping, metin.
"""
from dataclasses import dataclass
import hmac
import time

from . import protokol as p

HERKES = object()          # alici: tum dogrulanmis istemciler


@dataclass
class Ayarlar:
    token: str = ''
    tek_operator: bool = True


class RosArayuzu:
    """Cekirdegin ROS'tan istedikleri. Gercegi Faz 10'da (bridge_node), testlerde sahtesi."""

    def metin_yayinla(self, metin):
        """Metni /voice/text'e yayinla (command_parser dinler)."""
        raise NotImplementedError


@dataclass(eq=False)          # kimlige gore karsilastir; sozluk anahtari olabilsin
class Istemci:
    ad: str
    dogrulandi: bool = False
    rol: str = 'izleyici'
    cihaz: str = ''
    son_mesaj_t: float = 0.0


class TelsizCekirdegi:

    def __init__(self, ros, ayarlar=None, saat=time.monotonic):
        self.ros = ros
        self.ayarlar = ayarlar or Ayarlar()
        self.saat = saat
        self.istemciler = []
        self.operator = None
        self.sayaclar = {'metin': 0}

    # ------------------------------------------------------------------ baglanti
    def baglandi(self, ad):
        istemci = Istemci(ad=ad, son_mesaj_t=self.saat())
        self.istemciler.append(istemci)
        return istemci

    def koptu(self, istemci):
        if istemci in self.istemciler:
            self.istemciler.remove(istemci)
        if istemci is self.operator:
            self.operator = None       # operatorluk bosa cikti; siradaki telefon alabilir
        return []

    # ------------------------------------------------------------------ gelenler
    def metin_cercevesi(self, istemci, ham):
        try:
            mesaj = p.json_coz(ham)
        except p.ProtokolHatasi as e:
            return [(istemci, p.json_yaz('hata', kod=e.kod, mesaj=str(e)))]
        istemci.son_mesaj_t = self.saat()
        tip = mesaj['tip']

        if tip == 'merhaba':
            return self._merhaba(istemci, mesaj)
        if not istemci.dogrulandi:
            return [(istemci, p.json_yaz('hata', kod='yetkisiz', mesaj='önce merhaba ile giriş yap'))]
        if tip == 'ping':
            return [(istemci, p.json_yaz('pong', t=mesaj.get('t'), sunucu_saati=time.time()))]
        if istemci is not self.operator:
            return [(istemci, p.json_yaz('hata', kod='operator_degil',
                                         mesaj='komut vermek için operatör olmalısın'))]
        if tip == 'metin':
            return self._metin(istemci, mesaj)
        return [(istemci, p.json_yaz('hata', kod='desteklenmiyor',
                                     mesaj=f'"{tip}" sonraki fazlarda eklenecek'))]

    def ikili_cerceve(self, istemci, veri):
        return []                      # ses Faz 8'de

    # ------------------------------------------------------------------ mesaj tipleri
    def _merhaba(self, istemci, mesaj):
        # compare_digest: karsilastirma suresi token'in kac harfinin dogru
        # oldugunu ele vermesin (zamanlama saldirisi).
        if not self.ayarlar.token or not hmac.compare_digest(
                mesaj['token'].encode(), self.ayarlar.token.encode()):
            return [(istemci, p.json_yaz('hata', kod='yetkisiz', mesaj='token hatalı'))]
        if mesaj.get('surum', p.SURUM) != p.SURUM:
            return [(istemci, p.json_yaz('hata', kod='surum',
                                         mesaj=f'protokol sürümü {p.SURUM} bekleniyor'))]
        istemci.dogrulandi = True
        istemci.cihaz = str(mesaj.get('cihaz', ''))[:60]
        cikti = []
        istenen = mesaj['rol']
        if istenen == 'operator' and (self.operator is None or not self.ayarlar.tek_operator):
            istemci.rol = 'operator'
            self.operator = istemci
        else:
            istemci.rol = 'izleyici'
            if istenen == 'operator':
                cikti.append((istemci, p.json_yaz(
                    'hata', kod='operator_dolu',
                    mesaj='başka bir operatör bağlı; izleyici olarak bağlandın')))
        cikti.insert(0, (istemci, p.json_yaz(
            'hos_geldin', surum=p.SURUM, rol=istemci.rol, yer_stt=False,
            sunucu_saati=time.time())))
        return cikti

    def _metin(self, istemci, mesaj):
        metin = mesaj['metin'].strip()
        if not metin:
            return [(istemci, p.json_yaz('anlasilmadi', id=mesaj['id'], sebep='boş metin'))]
        self.sayaclar['metin'] += 1
        self.ros.metin_yayinla(metin[:500])
        return [(HERKES, p.json_yaz('duyuldu', id=mesaj['id'], metin=metin[:500],
                                    kaynak=str(mesaj.get('kaynak', 'klavye')), stt_ms=None))]

    # ------------------------------------------------------------------ zamanlayici
    def tik(self):
        """Duzenli cagrilir (0.5 sn). Faz 6'da kalp atisi kontrolu buraya gelecek."""
        return []
