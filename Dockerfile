# =============================================================================
# Embedded Linux Essentials - Development Environment
# =============================================================================
# This Dockerfile creates a complete development environment for all labs
# and exercises targeting BeagleBone Black Rev C (AM335x Cortex-A8)
#
# Build:  docker build -t embedded-linux-essentials .
# Run:    docker run -it --rm -v $(pwd):/workspace embedded-linux-essentials
#
# For USB/Serial access, run with:
#   docker run -it --rm --privileged -v /dev:/dev -v $(pwd):/workspace embedded-linux-essentials
# =============================================================================

FROM ubuntu:22.04

LABEL maintainer="Embedded Linux Essentials"
LABEL description="Complete development environment for Embedded Linux labs targeting BeagleBone Black"
LABEL version="1.0"

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# =============================================================================
# Core Build Dependencies
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Basic utilities
    sudo \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    # Version control
    git \
    # Build essentials
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    ninja-build \
    # Kernel/U-Boot build dependencies
    bc \
    bison \
    flex \
    libssl-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libelf-dev \
    # Additional build tools
    autoconf \
    automake \
    libtool \
    pkg-config \
    # Compression tools
    gzip \
    bzip2 \
    xz-utils \
    lzop \
    zstd \
    cpio \
    # Python (for kernel scripts and tools)
    python3 \
    python3-pip \
    python3-dev \
    python3-setuptools \
    python-is-python3 \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Cross-Compilation Toolchain (ARM 32-bit for BeagleBone Black)
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    crossbuild-essential-armhf \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    # For 64-bit ARM (optional, for other boards)
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# U-Boot and Device Tree Tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    u-boot-tools \
    device-tree-compiler \
    # For FIT image creation
    libfdt-dev \
    swig \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Serial Console and Communication Tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    minicom \
    picocom \
    screen \
    # USB utilities
    usbutils \
    # For serial port access
    setserial \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Network Boot Infrastructure (TFTP, NFS, DHCP)
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # TFTP server
    tftpd-hpa \
    tftp-hpa \
    # NFS server
    nfs-kernel-server \
    nfs-common \
    # DHCP server (for network boot)
    dnsmasq \
    # Network utilities
    iproute2 \
    iputils-ping \
    net-tools \
    netcat-openbsd \
    tcpdump \
    bridge-utils \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Filesystem and Image Tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Filesystem tools
    e2fsprogs \
    dosfstools \
    mtools \
    mtd-utils \
    # Disk/partition tools
    parted \
    gdisk \
    fdisk \
    # Image manipulation
    squashfs-tools \
    genext2fs \
    # Loopback device support
    kmod \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Debugging and Analysis Tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # GDB for ARM
    gdb-multiarch \
    # Binary analysis
    binutils \
    file \
    xxd \
    hexedit \
    # Tracing
    strace \
    ltrace \
    # Performance
    linux-tools-generic \
    # Text processing
    gawk \
    sed \
    jq \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Documentation and Editor Tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Editors
    vim \
    nano \
    # Man pages
    man-db \
    manpages \
    manpages-dev \
    # Documentation tools
    texinfo \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Buildroot and Yocto Dependencies
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Buildroot dependencies
    libncurses5 \
    rsync \
    unzip \
    # Yocto dependencies
    chrpath \
    diffstat \
    gawk \
    texinfo \
    zstd \
    liblz4-tool \
    locales \
    # Additional Yocto requirements
    python3-git \
    python3-jinja2 \
    python3-pexpect \
    python3-pip \
    python3-subunit \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Real-Time Kernel Tools
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # RT testing tools
    rt-tests \
    # Kernel tracing
    trace-cmd \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Security Tools (for Secure Boot exercises)
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # OpenSSL for key generation
    openssl \
    libssl-dev \
    # Signing tools
    sbsigntool \
    # Certificate tools
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Configure Locale (required for Yocto)
# =============================================================================
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# =============================================================================
# Create Non-Root User for Yocto (Yocto doesn't run as root)
# =============================================================================
ARG USERNAME=developer
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Add user to dialout group for serial port access
RUN usermod -a -G dialout $USERNAME

# =============================================================================
# Setup TFTP Server
# =============================================================================
RUN mkdir -p /srv/tftp && chmod 777 /srv/tftp
RUN echo 'TFTP_USERNAME="tftp"\nTFTP_DIRECTORY="/srv/tftp"\nTFTP_ADDRESS=":69"\nTFTP_OPTIONS="--secure --create"' > /etc/default/tftpd-hpa

# =============================================================================
# Setup NFS Server
# =============================================================================
RUN mkdir -p /srv/nfs/rootfs && chmod 777 /srv/nfs/rootfs
RUN echo '/srv/nfs/rootfs *(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports

# =============================================================================
# Environment Variables for Cross-Compilation
# =============================================================================
ENV ARCH=arm
ENV CROSS_COMPILE=arm-linux-gnueabihf-
ENV PATH="/usr/bin:${PATH}"

# Convenience aliases
RUN echo 'alias ll="ls -la"' >> /etc/bash.bashrc \
    && echo 'alias arm-gcc="arm-linux-gnueabihf-gcc"' >> /etc/bash.bashrc \
    && echo 'alias arm-objdump="arm-linux-gnueabihf-objdump"' >> /etc/bash.bashrc \
    && echo 'alias arm-readelf="arm-linux-gnueabihf-readelf"' >> /etc/bash.bashrc

# =============================================================================
# Workspace Setup
# =============================================================================
WORKDIR /workspace

# Create directory structure for labs
RUN mkdir -p /workspace/build \
    && mkdir -p /workspace/downloads \
    && mkdir -p /workspace/output \
    && chown -R $USERNAME:$USERNAME /workspace

# =============================================================================
# Startup Script
# =============================================================================
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# =============================================================================
# Switch to Non-Root User
# =============================================================================
USER $USERNAME

# =============================================================================
# Default Command
# =============================================================================
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["/bin/bash"]
