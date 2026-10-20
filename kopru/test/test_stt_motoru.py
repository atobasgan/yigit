"""STT motoru: secim + (istege bagli) gercek faster-whisper testi."""
import os
import struct

import pytest

from mobile_bridge.stt_motoru import DRONE_SOZLUGU, STTHatasi, STTMotoru, motor_olustur


def test_yok_motoru():
    m = motor_olustur('yok')
    assert isinstance(m, STTMotoru) and not m.hazir
    with pytest.raises(STTHatasi):
        m.yaziya_cevir(b'', 16000)


def test_bilinmeyen_motor():
    with pytest.raises(STTHatasi):
        motor_olustur('sihirli')


def test_drone_sozlugu_komutlari_icerir():
    for kelime in ('yüksel', 'alçal', 'metre', 'kuzeye', 'dur'):
        assert kelime in DRONE_SOZLUGU


@pytest.mark.skipif(not os.environ.get('TELSIZ_GERCEK_STT'),
                    reason='model indirir; çalıştırmak için TELSIZ_GERCEK_STT=1')
def test_gercek_faster_whisper_sessizlik():
    m = motor_olustur('faster_whisper', model='tiny', hesaplama='int8')
    assert m.hazir
    assert isinstance(m.yaziya_cevir(struct.pack('<h', 0) * 16000, 16000), str)
