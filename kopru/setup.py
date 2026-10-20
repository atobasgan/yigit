from setuptools import find_packages, setup

package_name = 'mobile_bridge'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools', 'websockets'],
    zip_safe=True,
    maintainer='atobasgan',
    maintainer_email='atobasgan33@gmail.com',
    description='Mobil telsiz uygulamasi ile ROS 2 arasinda WebSocket koprusu.',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'bridge_node = mobile_bridge.bridge_node:main',
            'sahte_telefon = mobile_bridge.sahte_telefon:main',
            'deneme_sunucusu = mobile_bridge.deneme_sunucusu:main',
        ],
    },
)
