"""Drone reposundaki command_parser ve mission_executor'i bulur.

Komutu ANLAYAN kod (normalize, hizli yol, LLM, guvenlik) drone reposunda;
bu repo onu kopyalamaz, yanindaki drone reposunu kullanir:

    export DRONE_REPO=~/drone          # varsayilan: bu reponun yanindaki ../drone
"""
import os
import sys

KOK = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAKETLER = ('command_parser', 'mission_executor')


def drone_reposu():
    return os.path.expanduser(os.environ.get('DRONE_REPO') or os.path.join(KOK, '..', 'drone'))


def yolu_ekle():
    """Paketleri sys.path'e ekler. Bulunamazsa False."""
    src = os.path.join(drone_reposu(), 'ros2_ws', 'src')
    if not os.path.isdir(os.path.join(src, 'command_parser')):
        return False
    for paket in PAKETLER:
        yol = os.path.join(src, paket)
        if yol not in sys.path:
            sys.path.insert(0, yol)
    return True
