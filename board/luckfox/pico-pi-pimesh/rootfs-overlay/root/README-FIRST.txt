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

The wrapper clones stock upstream pyMC_Repeater to:
  /root/pyMC_Repeater

After that, you can also run the repo directly:
  cd /root/pyMC_Repeater
  bash buildroot-manage.sh status
