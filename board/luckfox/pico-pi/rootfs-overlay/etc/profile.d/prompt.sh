#!/bin/sh

if [ -n "${PS1:-}" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    export PS1='[\u \W]# '
  else
    export PS1='[\u \W]$ '
  fi
fi
