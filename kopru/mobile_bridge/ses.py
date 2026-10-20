"""PCM16 yardimcilari: konusmayi biriktirme, sure, seviye, WAV kaydi."""
from dataclasses import dataclass, field
import math
import os
import struct
import wave

from .protokol import ORNEK_BAYT, ORNEKLEME_HZ


def sure_s(pcm, hz=ORNEKLEME_HZ):
    return len(pcm) / ORNEK_BAYT / hz


def rms_dbfs(pcm):
    """Ses seviyesi (dBFS). Sessizlik -> -inf yerine -120."""
    n = len(pcm) // ORNEK_BAYT
    if n == 0:
        return -120.0
    ornekler = struct.unpack(f'<{n}h', pcm[:n * ORNEK_BAYT])
    ort = sum(o * o for o in ornekler) / n
    if ort <= 0:
        return -120.0
    return 20 * math.log10(math.sqrt(ort) / 32768.0)


@dataclass
class Konusma:
    """Bir bas-konus konusmasinin parcalari. Parcalar sira numarasina gore birlesir."""
    konusma_id: int
    t_basla: float
    parcalar: dict = field(default_factory=dict)
    bayt: int = 0
    t_bitti: float = None
    kayit_yolu: str = None             # kayit acikken WAV dosyasi

    def ekle(self, sira, pcm, en_fazla_bayt):
        """Parcayi ekler. Sinir asilirsa False dondurur (parca alinmaz)."""
        if sira in self.parcalar:
            return True                 # tekrar gelen parca: yok say
        if self.bayt + len(pcm) > en_fazla_bayt:
            return False
        self.parcalar[sira] = pcm
        self.bayt += len(pcm)
        return True

    def eksik_parcalar(self):
        if not self.parcalar:
            return []
        return [i for i in range(max(self.parcalar) + 1) if i not in self.parcalar]

    def pcm(self):
        return b''.join(self.parcalar[i] for i in sorted(self.parcalar))


def wav_kaydet(yol, pcm, hz=ORNEKLEME_HZ):
    """16 bit mono WAV yazar (Faz 3 Gorev 3.1 test kayitlari icin)."""
    os.makedirs(os.path.dirname(yol) or '.', exist_ok=True)
    with wave.open(yol, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(ORNEK_BAYT)
        w.setframerate(hz)
        w.writeframes(pcm)


def wav_oku(yol):
    """WAV dosyasini (pcm_bayt, hz) olarak okur; 16 bit mono bekler."""
    with wave.open(yol, 'rb') as w:
        if w.getsampwidth() != ORNEK_BAYT or w.getnchannels() != 1:
            raise ValueError(f'{yol}: 16 bit mono WAV bekleniyor')
        return w.readframes(w.getnframes()), w.getframerate()
