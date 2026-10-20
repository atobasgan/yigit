"""Telsiz (mobil uygulama) ile tum sistem: kopru + parser + yurutucu.

    export TELSIZ_TOKEN=benim-gizli-anahtarim     # istege bagli
    ros2 launch drone_bringup telsiz.launch.py
    ros2 launch drone_bringup telsiz.launch.py yurutucu:=false   # sadece kopru + parser

PX4 SITL, MicroXRCEAgent ve llama-server ayri surecler (scripts/hepsini_baslat.sh).
"""
import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    paylasim = get_package_share_directory('drone_bringup')
    launch_dir = os.path.join(paylasim, 'launch')

    def dahil(ad, kosul=None):
        return IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(launch_dir, ad)), condition=kosul)

    return LaunchDescription([
        DeclareLaunchArgument('telsiz', default_value=os.path.join(paylasim, 'config', 'telsiz.yaml')),
        DeclareLaunchArgument('yurutucu', default_value='true'),
        Node(
            package='mobile_bridge',
            executable='bridge_node',
            name='mobile_bridge',
            parameters=[LaunchConfiguration('telsiz')],
            output='screen',
            emulate_tty=True,
        ),
        dahil('parser.launch.py'),
        dahil('executor.launch.py', IfCondition(LaunchConfiguration('yurutucu'))),
    ])
