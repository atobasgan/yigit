"""mobile_bridge: telefon (telsiz) <-> ROS 2 koprusu.

    ros2 run mobile_bridge bridge_node
    ros2 launch drone_bringup telsiz.launch.py

Telefondan gelen:
  metin (telefonda taninmis)  -> /voice/text            (command_parser isler)
  ses   (bas-konus)           -> STT (istege bagli)     -> /voice/text
                              -> /voice/utterance       (Faz 3 stt_node icin)
  ACIL DUR                    -> /drone/emergency_stop  (LLM/STT'ye ugramaz)
Telefona giden:
  /drone/command  -> "komut" (LLM/hizli yol JSON'u, gecikme)
  /drone/feedback -> "geri_bildirim" / "anlasilmadi"
  PX4 telemetrisi -> "telemetri" (2 Hz)
"""
from concurrent.futures import ThreadPoolExecutor
import asyncio
import logging
import os
import secrets
import threading
import time

from drone_interfaces.msg import CommandList, Feedback
import rclpy
from rclpy.node import Node
from rclpy.time import Time
from std_msgs.msg import Empty, String

from . import protokol
from .cekirdek import Ayarlar, RosArayuzu, TelsizCekirdegi
from .donustur import komut_listesi_sozlugu, telemetri_sozlugu
from .qr_kod import terminale_yaz, yerel_ip
from .stt_motoru import STTHatasi, motor_olustur
from .sunucu import TelsizSunucusu

try:
    from drone_interfaces.msg import AudioUtterance
except ImportError:          # drone_interfaces eski derlemeyse
    AudioUtterance = None

try:
    from mission_executor.px4_interface import PX4Arayuz
except ImportError:          # px4_msgs yoksa telemetri gonderilmez
    PX4Arayuz = None


class _RosKoprusu(RosArayuzu):
    """Cekirdegin ROS isteklerini node uzerinden yapar."""

    def __init__(self, node):
        self.node = node

    def metin_yayinla(self, metin):
        self.node.metin_pub.publish(String(data=metin))

    def acil_dur_yayinla(self):
        self.node.acil_pub.publish(Empty())
        self.node.get_logger().warn('ACİL DUR yayınlandı (telsiz)')

    def konusma_yayinla(self, konusma, kaynak):
        if self.node.konusma_pub is None:
            return
        import array
        msg = AudioUtterance()
        msg.id = konusma.konusma_id
        msg.kaynak = kaynak
        msg.ornekleme_hz = protokol.ORNEKLEME_HZ
        msg.ornekler = array.array('h', konusma.pcm())
        simdi = self.node.get_clock().now()
        sure_ns = int((konusma.t_bitti - konusma.t_basla) * 1e9)
        msg.t_konusma_bitti = simdi.to_msg()
        msg.t_konusma_basladi = Time(nanoseconds=simdi.nanoseconds - sure_ns).to_msg()
        self.node.konusma_pub.publish(msg)

    def stt_baslat(self, konusma):
        self.node.stt_isleri.submit(self.node.stt_calistir, konusma)


class BridgeNode(Node):

    def __init__(self):
        super().__init__('mobile_bridge')
        p = self.declare_parameter
        host = p('host', '0.0.0.0').value
        port = int(p('port', 8765).value)
        token_env = p('token_env', 'TELSIZ_TOKEN').value
        ilan_ip = p('ilan_ip', '').value or yerel_ip()
        telemetri_hz = float(p('telemetri_hz', 2.0).value)

        token = os.environ.get(token_env, '')
        if not token:
            token = secrets.token_urlsafe(9)
            self.get_logger().warn(
                f'{token_env} ortam değişkeni yok; bu oturum için rastgele token üretildi')

        ayarlar = Ayarlar(
            token=token,
            tek_operator=p('tek_operator', True).value,
            en_uzun_konusma_s=float(p('en_uzun_konusma_s', 15.0).value),
            en_kisa_konusma_s=float(p('en_kisa_konusma_s', 0.25).value),
            baglanti_zaman_asimi_s=float(p('baglanti_zaman_asimi_s', 3.0).value),
            baglanti_koparsa=p('baglanti_koparsa', 'dur').value,
            kayit_klasoru=os.path.expanduser(p('kayit_klasoru', '').value),
        )

        # --- STT motoru (istege bagli) ---
        self.stt = None
        motor_adi = p('stt_motoru', 'yok').value
        try:
            ayar = {}
            if motor_adi == 'faster_whisper':
                ayar = dict(model=p('stt_model', 'small').value,
                            cihaz=p('stt_cihaz', 'auto').value,
                            hesaplama=p('stt_hesaplama', 'default').value,
                            beam_size=int(p('stt_beam_size', 1).value))
            self.stt = motor_olustur(motor_adi, **ayar)
            if self.stt.hazir:
                self.get_logger().info(f'STT motoru {motor_adi}: ısınma {self.stt.isit():.0f} ms')
        except STTHatasi as e:
            self.get_logger().error(f'STT motoru kurulamadı ({e}); yalnızca telefon STT modu çalışır')
            self.stt = motor_olustur('yok')
        self.stt_isleri = ThreadPoolExecutor(max_workers=1, thread_name_prefix='stt')

        # --- ROS ---
        self.metin_pub = self.create_publisher(String, '/voice/text', 10)
        self.acil_pub = self.create_publisher(Empty, '/drone/emergency_stop', 10)
        self.konusma_pub = (self.create_publisher(AudioUtterance, '/voice/utterance', 10)
                            if AudioUtterance else None)
        self.create_subscription(CommandList, '/drone/command', self._komut_cb, 10)
        self.create_subscription(Feedback, '/drone/feedback', self._geri_bildirim_cb, 10)

        self.cekirdek = TelsizCekirdegi(_RosKoprusu(self), ayarlar,
                                        stt_hazir=self.stt.hazir, stt_adi=self.stt.ad)
        self.sunucu = TelsizSunucusu(self.cekirdek, host, port)
        self._thread = threading.Thread(target=self._sunucu_dongusu, daemon=True)
        self._thread.start()

        self.px4 = None
        if PX4Arayuz is not None and telemetri_hz > 0:
            self.px4 = PX4Arayuz(self, komut_yayinlari=False)
            self.create_timer(1.0 / telemetri_hz, self._telemetri_tik)

        adres = protokol.baglanti_adresi(ilan_ip, port, token)
        self.get_logger().info(
            f'Telsiz köprüsü hazır. Telefonda bu adresi okut ya da yaz:\n{adres}\n'
            f'{terminale_yaz(adres)}\n'
            f'STT: {self.stt.ad} | bağlantı koparsa: {ayarlar.baglanti_koparsa} | '
            f'kayıt: {ayarlar.kayit_klasoru or "kapalı"}')

    def _sunucu_dongusu(self):
        logging.basicConfig(level=logging.INFO)
        try:
            asyncio.run(self.sunucu.calis())
        except OSError as e:
            self.get_logger().fatal(f'WebSocket sunucusu açılamadı: {e}')

    # ------------------------------------------------------------------ STT
    def stt_calistir(self, konusma):
        t0 = time.perf_counter()
        try:
            metin = self.stt.yaziya_cevir(konusma.pcm(), protokol.ORNEKLEME_HZ)
            hata = None
        except Exception as e:  # STT hatasi koprunun calismasini durdurmamali
            metin, hata = '', f'STT hatası: {e}'
        sure = (time.perf_counter() - t0) * 1000
        self.get_logger().info(f'STT #{konusma.konusma_id}: "{metin}" ({sure:.0f} ms)')
        self.sunucu.disaridan(self.cekirdek.stt_sonucu, konusma, metin, sure, hata)

    # ------------------------------------------------------------------ ROS callback'leri
    def _komut_cb(self, msg):
        self.sunucu.disaridan(self.cekirdek.ros_komut, komut_listesi_sozlugu(msg))

    def _geri_bildirim_cb(self, msg):
        self.sunucu.disaridan(self.cekirdek.ros_geri_bildirim, msg.durum, msg.mesaj)

    def _telemetri_tik(self):
        self.sunucu.disaridan(self.cekirdek.telemetri, telemetri_sozlugu(self.px4))

    def destroy_node(self):
        self.sunucu.durdur()
        self.stt_isleri.shutdown(wait=False)
        super().destroy_node()


def main(args=None):
    rclpy.init(args=args)
    node = BridgeNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
