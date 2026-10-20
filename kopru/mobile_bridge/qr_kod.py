"""Baglanti adresini terminalde QR kod olarak gosterir (telefon okutur)."""
import socket


def yerel_ip():
    """Varsayilan ag arayuzunun IP'si. Paket gondermez (UDP connect sadece rota secer)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))
        return s.getsockname()[0]
    except OSError:
        return '127.0.0.1'
    finally:
        s.close()


def terminale_yaz(metin):
    """qrcode paketi varsa ASCII QR, yoksa sadece metin dondurur."""
    try:
        import io

        import qrcode
    except ImportError:
        return '(QR icin: pip install qrcode)'
    qr = qrcode.QRCode(border=1)
    qr.add_data(metin)
    qr.make(fit=True)
    tampon = io.StringIO()
    qr.print_ascii(out=tampon, invert=True)
    return tampon.getvalue()
