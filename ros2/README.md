# ros2/ — drone reposuna eklenecek ROS 2 parçaları (Faz 10)

Telsiz köprüsü (`kopru/`) gerçek sistemde bir **ROS 2 paketi** olarak çalışır
(`mobile_bridge`). Onun drone reposunda ihtiyaç duyduğu küçük değişiklikler
burada duruyor. Okuması kolay olsun diye dosyalar ayrıca kopyalandı; hepsini
tek seferde uygulamak için `drone_reposu.patch` var.

| Dosya | Ne işe yarar |
|---|---|
| `drone_interfaces/msg/AudioUtterance.msg` | Bas-konuş ile alınmış ham konuşma (`/voice/utterance`). İleride ayrı bir `stt_node` bunu dinleyebilir. |
| `drone_bringup/launch/telsiz.launch.py` | Köprü + parser + yürütücüyü birlikte başlatır. |
| `drone_bringup/config/telsiz.yaml` | Köprünün parametreleri (port, token, STT modeli, telsiz koparsa ne olsun...). |
| `drone_reposu.patch` | Yukarıdakiler + `parser_node` ACİL DUR nesli + `Feedback.msg` `iptal` durumu + `px4_interface(komut_yayinlari=False)` + `drone_bringup/package.xml` + `drone_interfaces/CMakeLists.txt`. |

## Uygulama

```bash
cd ~/drone
git apply ~/yigit/ros2/drone_reposu.patch      # drone reposunun main dalına uygulanır
ln -s ~/yigit/kopru ros2_ws/src/mobile_bridge   # köprüyü ROS çalışma alanına bağla
cd ros2_ws && colcon build --symlink-install && source install/setup.bash
ros2 launch drone_bringup telsiz.launch.py
```

`git apply --check` ile önce denenebilir. Ayrıntılar: [docs/FAZ_10](../docs/FAZ_10_butun_sistem.md).
