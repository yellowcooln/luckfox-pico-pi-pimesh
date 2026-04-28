FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
  autoconf \
  bc \
  bison \
  build-essential \
  cmake \
  cpio \
  curl \
  device-tree-compiler \
  expect \
  fakeroot \
  file \
  flex \
  g++-multilib \
  gawk \
  gcc-multilib \
  git \
  gperf \
  libncurses5-dev \
  libssl-dev \
  module-assistant \
  openssh-client \
  openssh-server \
  passwd \
  pkg-config \
  python-is-python3 \
  rsync \
  ssh \
  sudo \
  texinfo \
  unzip \
  vim \
  zip \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/pymc-build-home \
  && chmod 0777 /tmp/pymc-build-home

WORKDIR /workspace

ENV HOME=/tmp/pymc-build-home

CMD ["/bin/bash"]
