FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG HOST_UID=1000
ARG HOST_GID=1000

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

RUN groupadd -g "${HOST_GID}" builder \
  && useradd -m -u "${HOST_UID}" -g "${HOST_GID}" -s /bin/bash builder \
  && echo 'builder ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/builder \
  && chmod 0440 /etc/sudoers.d/builder

WORKDIR /workspace
USER builder

ENV HOME=/home/builder

CMD ["/bin/bash"]
