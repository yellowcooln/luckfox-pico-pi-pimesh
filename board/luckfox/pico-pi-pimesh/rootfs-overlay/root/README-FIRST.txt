pyMC Repeater Buildroot image notes

Helper files are preloaded at:
  /opt/pymc-repeater-buildroot

Convenience symlink:
  /root/pymc-repeater-buildroot

Typical first steps:
  cd /root/pymc-repeater-buildroot
  sh buildroot-manage.sh doctor
  sh buildroot-manage.sh install
  sh buildroot-manage.sh start logs
