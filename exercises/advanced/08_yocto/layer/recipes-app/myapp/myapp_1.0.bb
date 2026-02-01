SUMMARY = "Example application for BeagleBone Black"
DESCRIPTION = "Demonstrates custom Yocto recipe for BBB"
HOMEPAGE = "https://github.com/example/myapp"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Source files from local files/ directory
SRC_URI = "file://myapp.c \
           file://Makefile"

# Working directory
S = "${WORKDIR}"

# Build dependencies
# DEPENDS = "libgpiod"

# Runtime dependencies
# RDEPENDS:${PN} = "libgpiod"

# Compile
do_compile() {
    oe_runmake
}

# Install
do_install() {
    install -d ${D}${bindir}
    install -m 0755 myapp ${D}${bindir}
}

# Package files
FILES:${PN} = "${bindir}/myapp"
