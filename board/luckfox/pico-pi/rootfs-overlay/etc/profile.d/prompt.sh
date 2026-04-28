#!/bin/sh

# Use BusyBox ash fancy prompt escapes so SSH/login shells look like Debian:
# root@luckfox:~#  and  user@luckfox:~$
if [ -n "${PS1:-}" ]; then
  PS1='\u@\h:\w\$ '
  export PS1
fi
