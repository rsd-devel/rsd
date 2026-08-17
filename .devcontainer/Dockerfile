FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-22.04

# Install dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    autoconf \
    automake \
    autotools-dev \
    curl \
    python3 \
    python3-pip \
    python3-tomli \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev \
    gawk \
    build-essential \
    bison \
    flex \
    texinfo \
    gperf \
    libtool \
    patchutils \
    bc \
    zlib1g-dev \
    libexpat-dev \
    ninja-build \
    git \
    cmake \
    libglib2.0-dev \
    libslirp-dev \
    device-tree-compiler \
    gcc-riscv64-unknown-elf \
    binutils-riscv64-unknown-elf \
    picolibc-riscv64-unknown-elf

# install verilator
RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends help2man perl g++ ccache
RUN git clone https://github.com/verilator/verilator \
    && cd verilator \
    && git checkout v4.228 \
    && git clone https://github.com/westes/flex .flex \
    && cd .flex \
    && git checkout v2.6.4 \
    && cd .. \
    && cp .flex/src/FlexLexer.h include/FlexLexer.h \
    && cp .flex/src/FlexLexer.h FlexLexer.h
RUN cd verilator \
    && autoconf \
    && ./configure \
    && make -j$(nproc) \
    && make install

RUN echo "export RSD_ROOT=/workspaces/$(basename '/workspaces/*/')/" >> /home/vscode/.bashrc

# install python requirements
COPY .devcontainer/requirements.txt /workspaces/requirements.txt
RUN pip3 install -r /workspaces/requirements.txt
