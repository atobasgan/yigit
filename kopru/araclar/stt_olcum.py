"""Kayitli WAV'lari farkli faster-whisper modellerinden gecirip sure ve ciktiyi olcer.

    python3 araclar/stt_olcum.py kayitlar/*.wav --modeller base small --hesaplama int8 float32

etiketler.csv varsa (Faz 9 kayit modu) 'beklenen_metin' ile karsilastirir.
"""
import argparse
import csv
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from mobile_bridge.ses import wav_oku  # noqa: E402
from mobile_bridge.stt_motoru import FasterWhisperMotoru  # noqa: E402


def beklenenler(wavlar):
    sonuc = {}
    for klasor in {os.path.dirname(w) for w in wavlar}:
        yol = os.path.join(klasor, 'etiketler.csv')
        if os.path.exists(yol):
            with open(yol, encoding='utf-8') as f:
                for satir in csv.DictReader(f, delimiter=';'):
                    if satir.get('beklenen_metin'):
                        sonuc[satir['dosya']] = satir['beklenen_metin']
    return sonuc


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('wavlar', nargs='+')
    ap.add_argument('--modeller', nargs='+', default=['base', 'small'])
    ap.add_argument('--hesaplama', nargs='+', default=['int8'])
    args = ap.parse_args()
    beklenen = beklenenler(args.wavlar)
    for model in args.modeller:
        for hes in args.hesaplama:
            m = FasterWhisperMotoru(model=model, cihaz='cpu', hesaplama=hes)
            m.isit()
            toplam, dogru = 0.0, 0
            print(f'\n=== {model} / {hes}')
            for w in args.wavlar:
                pcm, hz = wav_oku(w)
                t0 = time.perf_counter()
                metin = m.yaziya_cevir(pcm, hz)
                ms = (time.perf_counter() - t0) * 1000
                toplam += ms
                b = beklenen.get(os.path.basename(w))
                if b is None:
                    isaret = ''
                else:
                    isaret = ' ✓' if metin.strip(' .').lower() == b.lower() else f' ✗ ({b})'
                dogru += isaret == ' ✓'
                print(f'  {ms:6.0f} ms  {os.path.basename(w)}: "{metin}"{isaret}')
            print(f'  ortalama {toplam / len(args.wavlar):.0f} ms' +
                  (f', doğru {dogru}/{len(beklenen)}' if beklenen else ''))


if __name__ == '__main__':
    main()
