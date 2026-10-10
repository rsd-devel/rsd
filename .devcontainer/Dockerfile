FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04

# Install dependencies. The base image provides common shell utilities.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    # Download and check out public tool and benchmark sources.
    curl \
    git \
    # Run RSD generators/test drivers and install isolated Python dependencies.
    # tomli provides TOML parsing for tools that import it directly.
    python3 \
    python3-pip \
    python3-venv \
    python3-tomli \
    # ACT4 uses Ruby/UDB to validate ISA configurations and generate headers.
    # ruby-dev supplies headers for gems with native extensions.
    ruby \
    ruby-dev \
    # Compile Verilator and native Ruby gems; generate parsers and manuals.
    build-essential \
    autoconf \
    automake \
    autotools-dev \
    bison \
    flex \
    libtool \
    gawk \
    help2man \
    perl \
    ccache \
    # Compile/link bare-metal RISC-V tests and provide C headers/math libraries.
    gcc-riscv64-unknown-elf \
    binutils-riscv64-unknown-elf \
    picolibc-riscv64-unknown-elf \
    # Build ACT4 tests with the supported LLVM release from Ubuntu packages.
    # Clang compiles RISC-V code, LLD links it, and LLVM supplies binary tools.
    clang-22 \
    lld-22 \
    llvm-22 \
    && rm -rf /var/lib/apt/lists/*

# Build the pinned Verilator version used by the existing simulator.
# FlexLexer.h is taken from the matching Flex release for this Verilator version.
RUN git clone --depth=1 --branch v4.228 https://github.com/verilator/verilator \
    && cd verilator \
    && git clone --depth=1 --branch v2.6.4 https://github.com/westes/flex .flex \
    && cp .flex/src/FlexLexer.h include/FlexLexer.h \
    && cp .flex/src/FlexLexer.h FlexLexer.h
RUN cd verilator \
    && autoconf \
    && ./configure \
    && make -j$(nproc) \
    && make install

# Ubuntu protects system Python from pip installs. Keep RSD's Python
# requirements in a virtual environment, available to commands and login shells.
ENV VIRTUAL_ENV=/opt/rsd-venv
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
COPY requirements.txt /workspaces/requirements.txt
RUN python3 -m venv "$VIRTUAL_ENV" \
    && pip3 install --no-cache-dir -r /workspaces/requirements.txt
