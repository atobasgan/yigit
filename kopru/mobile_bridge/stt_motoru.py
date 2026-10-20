"""Yer istasyonunda sesi yaziya ceviren motor (istege bagli).

Telefon "yer STT" modunda ham ses gonderir; kopru bu motorla yaziya cevirip
/voice/text'e yayinlar. Drone reposunda (Faz 3) ayri bir stt_node yazildiginda
kopru motoru kapatip yalnizca /voice/utterance yayinlayabilir (stt_motoru: yok).

Motorlar:
  yok            : ses yaziya cevrilmez (telefon STT modu kullanilir)
  faster_whisper : faster-whisper (pip install faster-whisper)
"""
import time

# Whisper'i drone sozlugune yatkinlastirir (MIMARI 3.6, initial_prompt)
DRONE_SOZLUGU = (
    'Drone komutları: kalk, kalkış yap, in, iniş yap, yüksel, alçal, metre, '
    'metreye çık, ileri, geri, sağa, sola, dön, derece, kuzeye, güneye, doğuya, '
    'batıya, git, dur, bekle, saniye, hızı ayarla, eve dön, en yakın hastane.'
)


class STTHatasi(RuntimeError):
    pass


class STTMotoru:
    ad = 'yok'
    hazir = False

    def yaziya_cevir(self, pcm, hz):
        raise STTHatasi('yer istasyonunda STT motoru yok')


class FasterWhisperMotoru(STTMotoru):
    ad = 'faster_whisper'

    def __init__(self, model='small', cihaz='auto', hesaplama='default',
                 dil='tr', beam_size=1, ilk_ipucu=DRONE_SOZLUGU):
        try:
            import numpy  # noqa: F401
            from faster_whisper import WhisperModel
        except ImportError as e:
            raise STTHatasi('faster-whisper kurulu değil: pip install faster-whisper') from e
        self.model_adi = model
        self.dil = dil
        self.beam_size = beam_size
        self.ilk_ipucu = ilk_ipucu
        self._model = WhisperModel(model, device=cihaz, compute_type=hesaplama)
        self.hazir = True

    def yaziya_cevir(self, pcm, hz):
        import numpy as np
        if hz != 16000:
            raise STTHatasi(f'16000 Hz bekleniyor, {hz} geldi')
        ses = np.frombuffer(pcm, dtype='<i2').astype(np.float32) / 32768.0
        bolumler, _ = self._model.transcribe(
            ses, language=self.dil, beam_size=self.beam_size,
            initial_prompt=self.ilk_ipucu, condition_on_previous_text=False,
            vad_filter=False, without_timestamps=True)
        return ' '.join(b.text.strip() for b in bolumler).strip()

    def isit(self):
        """Ilk istek yavas olur; acilista bos bir saniyeyi cevir."""
        t0 = time.perf_counter()
        self.yaziya_cevir(b'\x00\x00' * 16000, 16000)
        return (time.perf_counter() - t0) * 1000


def motor_olustur(ad, **ayarlar):
    """Ada gore motor dondurur. Kurulamazsa STTHatasi firlatir."""
    if ad in ('', 'yok', None):
        return STTMotoru()
    if ad == 'faster_whisper':
        return FasterWhisperMotoru(**ayarlar)
    raise STTHatasi(f'bilinmeyen STT motoru: {ad}')
