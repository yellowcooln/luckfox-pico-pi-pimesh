pyMC Repeater Buildroot image notes

Default login:
  user: root
  password: luckfox

Helper files are preloaded at:
  /opt/pymc-repeater-buildroot

Convenience symlink:
  /root/pymc-repeater-buildroot

This image boots as a normal Buildroot appliance using the vendor init/network
stack. It does not ship systemd.

Expected first steps after flashing:
  cd /root/pymc-repeater-buildroot
  sh buildroot-manage.sh doctor
  sh buildroot-manage.sh install
  sh buildroot-manage.sh start
  sh buildroot-manage.sh wait-ready
  sh buildroot-manage.sh advert

If you want to watch the repeater log:
  sh buildroot-manage.sh logs

During install, the pulled pyMC_Repeater repo helper asks for:
  - repeater name
  - admin password
  - radio profile
  - radio preset

and writes the initial config so the service can start without relying on the
web setup wizard.

You can rerun that later with:
  sh buildroot-manage.sh configure
  sh buildroot-manage.sh radio-profile

Tailscale helper:
  cd /root/pymc-repeater-buildroot
  sh tailscale-manage.sh install
  sh tailscale-manage.sh start
  sh tailscale-manage.sh up

Optional network priority helper:
  cd /root/pymc-repeater-buildroot
  edit /etc/default/network-priority
  edit /etc/network-priority.wifi
  sh network-priority.sh status
  /etc/init.d/S41network-priority start

This helper is off by default. When enabled, it prefers:
  - Ethernet first
  - Wi-Fi second
  - LTE last

based on the metrics configured in /etc/default/network-priority.

Basic Wi-Fi setup helper:
  cd /root/pymc-repeater-buildroot
  sh wifi-setup.sh

This lets you scan, save one SSID/PSK entry, render wpa_supplicant.conf,
and restart the Wi-Fi client without editing files by hand.

The wrapper clones stock upstream pyMC_Repeater to:
  /root/pyMC_Repeater

After that, you can also run the repo directly:
  cd /root/pyMC_Repeater
  bash buildroot-manage.sh status
