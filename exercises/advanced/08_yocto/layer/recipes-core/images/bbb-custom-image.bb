SUMMARY = "Custom BeagleBone Black image"
DESCRIPTION = "Full-featured embedded Linux image for BeagleBone Black"
LICENSE = "MIT"

# Base on core-image-base
require recipes-core/images/core-image-base.bb

# Additional image features
IMAGE_FEATURES += " \
    ssh-server-dropbear \
    tools-debug \
    debug-tweaks \
    "

# Core utilities
IMAGE_INSTALL += " \
    bash \
    coreutils \
    findutils \
    grep \
    sed \
    gawk \
    tar \
    gzip \
    less \
    vim \
    "

# Hardware tools
IMAGE_INSTALL += " \
    i2c-tools \
    spi-tools \
    devmem2 \
    evtest \
    usbutils \
    pciutils \
    "

# GPIO/PWM
IMAGE_INSTALL += " \
    libgpiod \
    libgpiod-tools \
    "

# Networking
IMAGE_INSTALL += " \
    iproute2 \
    iputils \
    ethtool \
    tcpdump \
    wget \
    curl \
    iperf3 \
    "

# Debugging
IMAGE_INSTALL += " \
    strace \
    ltrace \
    htop \
    lsof \
    procps \
    "

# Development (optional - increases image size)
# IMAGE_INSTALL += " \
#     python3 \
#     python3-pip \
#     git \
#     make \
#     "

# Custom packages from this layer
# IMAGE_INSTALL += " \
#     myapp \
#     "

# Root filesystem size (KB)
IMAGE_ROOTFS_SIZE = "262144"

# Extra space for packages installed at runtime
IMAGE_ROOTFS_EXTRA_SPACE = "102400"
